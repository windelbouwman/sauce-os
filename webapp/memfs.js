class TextFileWriter {
  constructor(fs, path) {
    this.fs = fs;
    this.path = path;
    this.parts = [];
  }

  writeText(text) {
    this.parts.push(text);
  }

  close() {
    let contents = this.parts.join("");
    this.fs.setFileContents(this.path, contents);
  }
}

class BinaryFileWriter {
  constructor(fs, path) {
    this.fs = fs;
    this.path = path;
    this.buffer = new Uint8Array(16);
    this.pointer = 0;
    this.length = 0;
  }

  writeData(data) {
    while (this.pointer + data.length > this.buffer.length) {
      let newBuf = new Uint8Array(this.buffer.length * 2);
      newBuf.set(this.buffer);
      this.buffer = newBuf;
    }
    this.buffer.set(data, this.pointer);
    this.pointer += data.length;
    if (this.pointer > this.length) {
      this.length = this.pointer;
    }
  }

  seek(position) {
    this.pointer = position;
  }

  tell() {
    return this.pointer;
  }

  close() {
    let contents = this.buffer.slice(0, this.length);
    this.fs.setFileContents(this.path, contents);
  }
}

class MemoryFS {
  constructor() {
    this.files = new Map();
    this.file_handles = new Map();
    this.handle_counter = 0;
  }

  fileExists(path) {
    return this.files.has(path);
  }

  setFileContents(path, contents) {
    this.files.set(path, contents);
  }

  getFileContents(path) {
    if (this.files.has(path)) {
      return this.files.get(path);
    } else {
      throw new Error("File not found: " + path);
    }
  }

  openFile(path, mode) {
    let handle = this.handle_counter;
    this.handle_counter += 1;
    let writer;
    if (mode == "w") {
      writer = new TextFileWriter(this, path);
    } else if (mode == "wb") {
      writer = new BinaryFileWriter(this, path);
    } else {
      throw new Error("Unknown mode: " + mode);
    }
    this.file_handles.set(handle, writer);
    return handle;
  }

  writeText(handle, text) {
    if (this.file_handles.has(handle)) {
      let f = this.file_handles.get(handle);
      f.writeText(text);
    } else {
      throw new Error("Invalid file handle:" + handle);
    }
  }

  writeData(handle, data) {
    if (this.file_handles.has(handle)) {
      let f = this.file_handles.get(handle);
      f.writeData(data);
    } else {
      throw new Error("Invalid file handle:" + handle);
    }
  }

  seek(handle, position) {
    if (this.file_handles.has(handle)) {
      let f = this.file_handles.get(handle);
      f.seek(position);
    } else {
      throw new Error("Invalid file handle:" + handle);
    }
  }

  tell(handle) {
    if (this.file_handles.has(handle)) {
      let f = this.file_handles.get(handle);
      return f.tell();
    } else {
      throw new Error("Invalid file handle:" + handle);
    }
  }

  closeFile(handle) {
    if (this.file_handles.has(handle)) {
      let f = this.file_handles.get(handle);
      f.close();
      this.file_handles.delete(handle);
    } else {
      throw new Error("Invalid file handle:" + handle);
    }
  }
}

export { MemoryFS };
