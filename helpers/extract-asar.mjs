#!/usr/bin/env node

// Minimal, dependency-free Electron ASAR extractor for architecture audits.
// It intentionally supports only the standard flat-file ASAR layout: unpacked
// entries already live next to the archive and are scanned from the package
// tree itself.

import fs from "node:fs";
import path from "node:path";

function fail(message) {
  console.error(`ASAR extraction failed: ${message}`);
  process.exit(1);
}

if (process.argv.length !== 6) {
  fail("usage: extract-asar.mjs <archive> <output> <max-files> <max-bytes>");
}

const [, , archive, output, maxFilesText, maxBytesText] = process.argv;
const maxFiles = Number(maxFilesText);
const maxBytes = Number(maxBytesText);

if (!Number.isSafeInteger(maxFiles) || maxFiles < 1) {
  fail("max-files must be a positive integer");
}
if (!Number.isSafeInteger(maxBytes) || maxBytes < 1) {
  fail("max-bytes must be a positive integer");
}

const archiveSize = fs.statSync(archive).size;
if (archiveSize < 16) fail("archive is shorter than its header");

const descriptor = fs.openSync(archive, "r");
const prefix = Buffer.alloc(16);
fs.readSync(descriptor, prefix, 0, prefix.length, 0);

// ASAR headers use two Chromium Pickles. The first contains the size of the
// second; the second contains a length-prefixed JSON string.
const sizePicklePayload = prefix.readUInt32LE(0);
const headerSize = prefix.readUInt32LE(4);
const headerPicklePayload = prefix.readUInt32LE(8);
const jsonSize = prefix.readUInt32LE(12);

if (sizePicklePayload !== 4 || headerSize < 8 || headerPicklePayload < 4) {
  fail("invalid pickle header");
}
if (jsonSize > headerPicklePayload - 4 || 8 + headerSize > archiveSize) {
  fail("invalid JSON header size");
}

const json = Buffer.alloc(jsonSize);
fs.readSync(descriptor, json, 0, json.length, 16);

let header;
try {
  header = JSON.parse(json.toString("utf8"));
} catch (error) {
  fail(`invalid JSON header: ${error.message}`);
}

if (!header || typeof header !== "object" || !header.files) {
  fail("header has no files table");
}

const dataOffset = 8 + headerSize;
const entries = [];
let totalBytes = 0;

function safePart(part) {
  return (
    typeof part === "string" &&
    part.length > 0 &&
    part !== "." &&
    part !== ".." &&
    !part.includes("\0") &&
    !part.includes("/") &&
    !part.includes("\\")
  );
}

function visit(files, parts = []) {
  if (!files || typeof files !== "object" || Array.isArray(files)) {
    fail("malformed files table");
  }

  for (const [name, entry] of Object.entries(files)) {
    if (!safePart(name) || !entry || typeof entry !== "object") {
      fail("unsafe or malformed ASAR entry");
    }

    const nextParts = [...parts, name];
    if (entry.files) {
      visit(entry.files, nextParts);
      continue;
    }

    // Electron stores these in <archive>.unpacked. The outer package walk
    // scans those real files, so copying placeholders would duplicate them.
    if (entry.unpacked || entry.link) continue;

    const size = Number(entry.size);
    const offset = Number(entry.offset);
    if (
      !Number.isSafeInteger(size) ||
      size < 0 ||
      !Number.isSafeInteger(offset) ||
      offset < 0
    ) {
      fail(`invalid offset or size for ${nextParts.join("/")}`);
    }
    if (dataOffset + offset + size > archiveSize) {
      fail(`entry extends past the archive: ${nextParts.join("/")}`);
    }

    totalBytes += size;
    if (entries.length + 1 > maxFiles || totalBytes > maxBytes) {
      fail("configured extraction limit exceeded");
    }
    entries.push({ parts: nextParts, size, offset });
  }
}

visit(header.files);
fs.mkdirSync(output, { recursive: true });

const chunkSize = 1024 * 1024;
for (const entry of entries) {
  const destination = path.join(output, ...entry.parts);
  const relative = path.relative(output, destination);
  if (relative.startsWith("..") || path.isAbsolute(relative)) {
    fail("entry escapes the extraction directory");
  }

  fs.mkdirSync(path.dirname(destination), { recursive: true });
  const target = fs.openSync(destination, "wx", 0o600);
  let remaining = entry.size;
  let sourcePosition = dataOffset + entry.offset;
  try {
    while (remaining > 0) {
      const chunk = Buffer.allocUnsafe(Math.min(chunkSize, remaining));
      const read = fs.readSync(
        descriptor,
        chunk,
        0,
        chunk.length,
        sourcePosition,
      );
      if (read !== chunk.length) fail("unexpected end of archive");
      fs.writeSync(target, chunk, 0, read);
      remaining -= read;
      sourcePosition += read;
    }
  } finally {
    fs.closeSync(target);
  }
}

fs.closeSync(descriptor);
