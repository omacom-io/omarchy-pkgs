#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";

if (process.argv.length !== 3) {
  throw new Error("usage: create-architecture-audit-fixtures.mjs <output>");
}

const output = process.argv[2];
fs.mkdirSync(output, { recursive: true });

function elf(machine) {
  const buffer = Buffer.alloc(64);
  buffer.set([0x7f, 0x45, 0x4c, 0x46, 2, 1, 1, 0], 0);
  buffer.writeUInt16LE(2, 16);
  buffer.writeUInt16LE(machine, 18);
  buffer.writeUInt32LE(1, 20);
  buffer.writeUInt16LE(64, 52);
  return buffer;
}

function asar(name, contents) {
  const header = JSON.stringify({
    files: {
      [name]: { size: contents.length, offset: "0" },
    },
  });
  const json = Buffer.from(header);
  const paddedJsonSize = (json.length + 3) & ~3;
  const headerPayloadSize = 4 + paddedJsonSize;
  const headerSize = 4 + headerPayloadSize;
  const prefix = Buffer.alloc(8 + headerSize);
  prefix.writeUInt32LE(4, 0);
  prefix.writeUInt32LE(headerSize, 4);
  prefix.writeUInt32LE(headerPayloadSize, 8);
  prefix.writeUInt32LE(json.length, 12);
  json.copy(prefix, 16);
  return Buffer.concat([prefix, contents]);
}

fs.writeFileSync(path.join(output, "aarch64.elf"), elf(183));
fs.writeFileSync(path.join(output, "x86_64.elf"), elf(62));
fs.writeFileSync(
  path.join(output, "nested-aarch64.asar"),
  asar("binding.node", elf(183)),
);
fs.writeFileSync(
  path.join(output, "nested-x86_64.asar"),
  asar("binding.node", elf(62)),
);

const macho = Buffer.alloc(64);
macho.set([0xcf, 0xfa, 0xed, 0xfe, 0x07, 0x00, 0x00, 0x01], 0);
macho.writeUInt32LE(3, 8);
macho.writeUInt32LE(8, 12);
fs.writeFileSync(path.join(output, "x86_64.node"), macho);

const pe = Buffer.alloc(512);
pe.write("MZ", 0, "ascii");
pe.writeUInt32LE(0x80, 0x3c);
pe.write("PE\0\0", 0x80, "binary");
pe.writeUInt16LE(0x8664, 0x84);
pe.writeUInt16LE(0, 0x86);
pe.writeUInt16LE(0xf0, 0x94);
pe.writeUInt16LE(0x0002, 0x96);
pe.writeUInt16LE(0x020b, 0x98);
pe.writeUInt16LE(3, 0xdc);
fs.writeFileSync(path.join(output, "x86_64.exe"), pe);

fs.writeFileSync(path.join(output, "malformed.asar"), Buffer.alloc(16));
