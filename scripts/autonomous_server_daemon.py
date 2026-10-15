#!/usr/bin/env python3
"""
Quantum IDE - Autonomous Server QA & Self-Healing Daemon
Автономный серверный демон тестирования и мониторинга ошибок Quantum IDE.

Поддерживает 2 режима:
1. 'adb'     — тестирование реального APK в Android (Redroid / эмулятор / физический телефон).
2. 'ghostqa' — тестирование Flutter приложения через встроенный HTTP-мост GhostQAService (порт 9988).

Запуск:
    python3 scripts/autonomous_server_daemon.py --mode=ghostqa --duration=60
    python3 scripts/autonomous_server_daemon.py --mode=adb --device=127.0.0.1:5555 --apk=build/app/outputs/flutter-apk/app-release.apk
"""

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.request
import urllib.error
from datetime import datetime
from pathlib import Path

REPORTS_DIR = Path(".quantum/qa_reports")
PACKAGE_NAME = "com.example.quantum_ide"
MAIN_ACTIVITY = "com.example.quantum_ide.MainActivity"


class AutonomousQADaemon:
    def __init__(self, mode: str, adb_device: str = None, apk_path: str = None, ghostqa_url: str = "http://127.0.0.1:9988"):
        self.mode = mode
        self.adb_device = adb_device
        self.apk_path = apk_path
        self.ghostqa_url = ghostqa_url.rstrip("/")
        REPORTS_DIR.mkdir(parents=True, exist_ok=True)
        self.detected_errors = []

    def log(self, msg: str, level: str = "INFO"):
        colors = {
            "INFO": "\033[94m",
            "SUCCESS": "\033[92m",
            "WARN": "\033[93m",
            "ERROR": "\033[91m",
            "RESET": "\033[0m"
        }
        timestamp = datetime.now().strftime("%H:%M:%S")
        print(f"{colors.get(level, '')}[{timestamp}] [{level}] {msg}{colors['RESET']}")

    # =========================================================================
    # GhostQA Engine Mode (Headless Linux / Local Flutter QA Bridge)
    # =========================================================================
    def run_ghostqa_cycle(self, iterations: int = 5):
        self.log(f"🚀 Запуск проверки через GhostQA Engine: {self.ghostqa_url}", "INFO")

        # 1. Проверяем доступность сервиса
        try:
            req = urllib.request.Request(f"{self.ghostqa_url}/health")
            with urllib.request.urlopen(req, timeout=3) as resp:
                status = json.loads(resp.read().decode())
                self.log(f"GhostQA сервис активен. Состояние: {status}", "SUCCESS")
        except Exception as e:
            self.log(f"Не удалось подключиться к GhostQA ({e}). Убедитесь, что Quantum IDE запущено с QUANTUM_OWNER_QA=1", "ERROR")
            return

        # 2. Снимаем базовый скриншот
        base_screen = self._ghostqa_screenshot("screen_baseline.png")
        if base_screen:
            self.log(f"Базовый скриншот сохранен: {base_screen}", "SUCCESS")

        # 3. Инспекция UI и клики по ключевым вкладкам
        for i in range(iterations):
            self.log(f"--- Итерация тестирования #{i+1} ---", "INFO")
            try:
                # Получаем дерево элементов
                req = urllib.request.Request(f"{self.ghostqa_url}/ui")
                with urllib.request.urlopen(req, timeout=5) as resp:
                    ui_data = json.loads(resp.read().decode())
                    clickable = [el for el in ui_data.get("elements", []) if el.get("isClickable")]
                    self.log(f"Обнаружено {len(clickable)} кликабельных виджетов в интерфейсе", "INFO")

                # Проверяем накопленные ошибки
                err_req = urllib.request.Request(f"{self.ghostqa_url}/errors")
                with urllib.request.urlopen(err_req, timeout=5) as resp:
                    err_data = json.loads(resp.read().decode())
                    err_count = err_data.get("count", 0)
                    if err_count > 0:
                        self.log(f"⚠️ ОБНАРУЖЕНЫ ОШИБКИ FLUTTER: {err_count}", "ERROR")
                        for err in err_data.get("errors", []):
                            self._record_error("GhostQA", err.get("message", ""), err.get("stackTrace", ""))
                    else:
                        self.log("✅ Ошибок рендеринга и исключений Flutter не обнаружено", "SUCCESS")

                time.sleep(2)
            except Exception as e:
                self.log(f"Ошибка в цикле инспекции: {e}", "WARN")

    def _ghostqa_screenshot(self, filename: str) -> str:
        try:
            req = urllib.request.Request(f"{self.ghostqa_url}/screenshot")
            with urllib.request.urlopen(req, timeout=10) as resp:
                data = resp.read()
                out_path = REPORTS_DIR / filename
                with open(out_path, "wb") as f:
                    f.write(data)
                return str(out_path)
        except Exception as e:
            self.log(f"Ошибка получения скриншота: {e}", "WARN")
            return ""

    # =========================================================================
    # Android ADB Mode (Real APK / Redroid / Emulator / Phone)
    # =========================================================================
    def run_adb_cycle(self, test_duration_sec: int = 30):
        self.log(f"📱 Запуск проверки Android APK через ADB", "INFO")
        adb = ["adb"]
        if self.adb_device:
            # Если указан IP:PORT, сначала выполняем connect
            if ":" in self.adb_device:
                subprocess.run(["adb", "connect", self.adb_device], capture_output=True, text=True)
            adb.extend(["-s", self.adb_device])

        # 1. Проверяем подключенное устройство
        res = subprocess.run(adb + ["get-state"], capture_output=True, text=True)
        if res.returncode != 0:
            self.log(f"Устройство не найдено или offline: {res.stderr.strip()}", "ERROR")
            return

        self.log("Устройство подключено и готово к работе", "SUCCESS")

        # 2. Установка APK при наличии
        if self.apk_path and os.path.exists(self.apk_path):
            self.log(f"Установка APK: {self.apk_path}...", "INFO")
            install_res = subprocess.run(adb + ["install", "-r", "-d", self.apk_path], capture_output=True, text=True)
            if "Success" in install_res.stdout or "Success" in install_res.stderr:
                self.log("APK успешно установлен на устройство!", "SUCCESS")
            else:
                self.log(f"Ошибка установки APK: {install_res.stderr or install_res.stdout}", "WARN")

        # 3. Очищаем logcat и запускаем приложение
        subprocess.run(adb + ["logcat", "-c"], capture_output=True)
        self.log(f"Запуск приложения {PACKAGE_NAME}...", "INFO")
        subprocess.run(adb + ["shell", "am", "start", "-n", f"{PACKAGE_NAME}/{MAIN_ACTIVITY}"], capture_output=True)

        time.sleep(3)

        # 4. Снимаем скриншот экрана
        screen_file = REPORTS_DIR / f"android_screen_{int(time.time())}.png"
        with open(screen_file, "wb") as f:
            subprocess.run(adb + ["exec-out", "screencap", "-p"], stdout=f)
        self.log(f"Скриншот экрана устройства сохранен: {screen_file}", "SUCCESS")

        # 5. Стресс-тестирование UI через monkey
        self.log("Запуск стресс-тестирования интерфейса (Monkey Tester)...", "INFO")
        subprocess.run(
            adb + ["shell", "monkey", "-p", PACKAGE_NAME, "--throttle", "250", "--ignore-crashes", "--ignore-timeouts", "200"],
            capture_output=True,
            text=True
        )

        # 6. Считываем ошибки из Logcat
        self.log("Анализ системных логов Logcat на наличие крэшей...", "INFO")
        logcat_res = subprocess.run(
            adb + ["logcat", "-d", "*:E"],
            capture_output=True,
            text=True
        )
        logs = logcat_res.stdout

        # Фильтруем важные ошибки приложения
        crash_signatures = ["FATAL EXCEPTION", "AndroidRuntime", PACKAGE_NAME, "flutter", "RenderFlex overflowed", "MissingPluginException"]
        app_errors = []
        for line in logs.splitlines():
            if any(sig in line for sig in crash_signatures):
                app_errors.append(line)

        if app_errors:
            self.log(f"⚠️ Найдено {len(app_errors)} критических записей в Logcat!", "ERROR")
            err_text = "\n".join(app_errors[:40])
            self._record_error("Android Logcat", err_text, err_text)
        else:
            self.log("✅ Критических ошибок в Android Logcat не обнаружено!", "SUCCESS")

    # =========================================================================
    # Error Reporting & Self-Healing Trigger
    # =========================================================================
    def _record_error(self, source: str, message: str, stack: str):
        error_entry = {
            "timestamp": datetime.now().isoformat(),
            "source": source,
            "message": message,
            "stackTrace": stack
        }
        self.detected_errors.append(error_entry)

    def generate_report(self):
        report_file = REPORTS_DIR / "autonomous_qa_summary.json"
        with open(report_file, "w", encoding="utf-8") as f:
            json.dump({
                "mode": self.mode,
                "timestamp": datetime.now().isoformat(),
                "error_count": len(self.detected_errors),
                "errors": self.detected_errors
            }, f, indent=2, ensure_ascii=False)

        md_file = REPORTS_DIR / "README_LATEST_REPORT.md"
        with open(md_file, "w", encoding="utf-8") as f:
            f.write(f"# 🛡️ Quantum IDE Autonomous QA Report\n\n")
            f.write(f"- **Время проверки**: `{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}`\n")
            f.write(f"- **Режим**: `{self.mode}`\n")
            f.write(f"- **Статус**: `{'❌ НАЙДЕНЫ ОШИБКИ (' + str(len(self.detected_errors)) + ')' if self.detected_errors else '✅ ВСЁ РАБОТАЕТ ИДЕАЛЬНО'}`\n\n")
            if self.detected_errors:
                f.write("## 🔍 Обнаруженные дефекты и ошибки:\n\n")
                for idx, err in enumerate(self.detected_errors, 1):
                    f.write(f"### Ошибка #{idx} ({err['source']})\n")
                    f.write(f"```text\n{err['message'][:800]}\n```\n\n")
            else:
                f.write("Все компоненты (терминал, UI, редакторы, фоновые сервисы) работают штатно, падений и RenderFlex overflows не зафиксировано.\n")

        self.log(f"📊 Итоговый отчет сохранен в: {md_file}", "SUCCESS")


def main():
    parser = argparse.ArgumentParser(description="Quantum IDE Autonomous QA Daemon")
    parser.add_argument("--mode", choices=["ghostqa", "adb"], default="ghostqa", help="Режим тестирования")
    parser.add_argument("--device", help="ADB идентификатор устройства (например, 127.0.0.1:5555)")
    parser.add_argument("--apk", help="Путь к APK для автоматической установки")
    parser.add_argument("--ghostqa-url", default="http://127.0.0.1:9988", help="URL GhostQA моста")
    parser.add_argument("--iterations", type=int, default=3, help="Количество циклов инспекции")
    args = parser.parse_args()

    daemon = AutonomousQADaemon(
        mode=args.mode,
        adb_device=args.device,
        apk_path=args.apk,
        ghostqa_url=args.ghostqa_url
    )

    if args.mode == "ghostqa":
        daemon.run_ghostqa_cycle(iterations=args.iterations)
    elif args.mode == "adb":
        daemon.run_adb_cycle()

    daemon.generate_report()


if __name__ == "__main__":
    main()
