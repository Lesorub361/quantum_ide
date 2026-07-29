const fs = require('fs');
const wasmBuffer = fs.readFileSync('/home/lesorub/Загрузки/quantum_ide/scratch/plugin.wasm');

const importObject = {
  env: {
    host_log: (ptr, len) => {
      const memory = inst.exports.memory;
      const buf = new Uint8Array(memory.buffer, ptr, len);
      const msg = new TextDecoder('utf-8').decode(buf);
      console.log("[WASM LOG]:", msg);
    }
  }
};

let inst;
WebAssembly.instantiate(wasmBuffer, importObject).then(result => {
  inst = result.instance;
  console.log("WASM loaded successfully!");
  console.log("Exports:", Object.keys(inst.exports));
  
  const input = "hello quantum ide wasm world!";
  const utf8Encoder = new TextEncoder();
  const inputBytes = utf8Encoder.encode(input);
  const inputLen = inputBytes.length;
  
  const inputPtr = inst.exports.alloc(inputLen);
  const memoryBuffer = new Uint8Array(inst.exports.memory.buffer);
  memoryBuffer.set(inputBytes, inputPtr);
  
  const resultPacked = inst.exports.run_plugin(1, inputPtr, inputLen);
  const packedBig = BigInt(resultPacked);
  const resultPtr = Number(packedBig >> 32n);
  const resultLen = Number(packedBig & 0xFFFFFFFFn);
  
  const resultBuffer = new Uint8Array(inst.exports.memory.buffer, resultPtr, resultLen);
  const outputText = new TextDecoder('utf-8').decode(resultBuffer);
  
  console.log("Input: ", input);
  console.log("Output:", outputText);
  
  inst.exports.dealloc(inputPtr, inputLen);
  inst.exports.dealloc(resultPtr, resultLen);
}).catch(err => {
  console.error("Error loading WASM:", err);
});
