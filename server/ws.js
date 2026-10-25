// Minimaler WebSocket-Server (RFC 6455), nur Textnachrichten. Keine Abhängigkeiten.
'use strict';
const crypto = require('crypto');
const { EventEmitter } = require('events');

const GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';
const MAX_MESSAGE = 64 * 1024;
const MAX_BUFFERED = 2 * 1024 * 1024;

class Connection extends EventEmitter {
  constructor(socket) {
    super();
    this.socket = socket;
    this.buf = Buffer.alloc(0);
    this.fragments = [];
    this.open = true;
    socket.setNoDelay(true);
    socket.on('data', (d) => {
      this.buf = this.buf.length ? Buffer.concat([this.buf, d]) : d;
      try {
        this.parse();
      } catch (e) {
        this.close();
      }
    });
    socket.on('close', () => this.finish());
    socket.on('error', () => this.finish());
  }

  finish() {
    if (!this.open) return;
    this.open = false;
    this.emit('close');
  }

  parse() {
    while (this.open) {
      const buf = this.buf;
      if (buf.length < 2) return;
      const fin = (buf[0] & 0x80) !== 0;
      const op = buf[0] & 0x0f;
      const masked = (buf[1] & 0x80) !== 0;
      let len = buf[1] & 0x7f;
      let off = 2;
      if (len === 126) {
        if (buf.length < 4) return;
        len = buf.readUInt16BE(2);
        off = 4;
      } else if (len === 127) {
        if (buf.length < 10) return;
        len = Number(buf.readBigUInt64BE(2));
        off = 10;
      }
      if (len > MAX_MESSAGE) return this.close();
      let mask = null;
      if (masked) {
        if (buf.length < off + 4) return;
        mask = buf.subarray(off, off + 4);
        off += 4;
      }
      if (buf.length < off + len) return;
      const payload = Buffer.from(buf.subarray(off, off + len));
      if (mask) for (let i = 0; i < payload.length; i++) payload[i] ^= mask[i & 3];
      this.buf = buf.subarray(off + len);

      if (op === 0x8) return this.close();
      if (op === 0x9) { this.frame(0xa, payload); continue; }
      if (op === 0xa) continue;
      if (op === 0x1 || op === 0x2 || op === 0x0) {
        this.fragments.push(payload);
        if (fin) {
          const msg = Buffer.concat(this.fragments).toString('utf8');
          this.fragments = [];
          if (msg.length > MAX_MESSAGE) return this.close();
          this.emit('message', msg);
        }
      }
    }
  }

  frame(op, payload) {
    if (!this.open) return;
    const len = payload.length;
    let header;
    if (len < 126) {
      header = Buffer.from([0x80 | op, len]);
    } else if (len < 65536) {
      header = Buffer.alloc(4);
      header[0] = 0x80 | op;
      header[1] = 126;
      header.writeUInt16BE(len, 2);
    } else {
      header = Buffer.alloc(10);
      header[0] = 0x80 | op;
      header[1] = 127;
      header.writeBigUInt64BE(BigInt(len), 2);
    }
    this.socket.write(Buffer.concat([header, payload]));
  }

  // droppable: bei langsamer Leitung lieber einen Snapshot auslassen als Puffer füllen
  send(text, droppable) {
    if (!this.open) return;
    if (droppable && this.socket.writableLength > MAX_BUFFERED) return;
    this.frame(0x1, Buffer.from(text, 'utf8'));
  }

  close() {
    if (this.open) {
      try { this.frame(0x8, Buffer.alloc(0)); } catch (e) { /* egal */ }
    }
    this.socket.end();
    this.finish();
  }
}

function handleUpgrade(req, socket) {
  const key = req.headers['sec-websocket-key'];
  if (!key || String(req.headers.upgrade).toLowerCase() !== 'websocket') {
    socket.destroy();
    return null;
  }
  const accept = crypto.createHash('sha1').update(key + GUID).digest('base64');
  socket.write(
    'HTTP/1.1 101 Switching Protocols\r\n' +
      'Upgrade: websocket\r\n' +
      'Connection: Upgrade\r\n' +
      'Sec-WebSocket-Accept: ' + accept + '\r\n\r\n'
  );
  return new Connection(socket);
}

module.exports = { handleUpgrade };
