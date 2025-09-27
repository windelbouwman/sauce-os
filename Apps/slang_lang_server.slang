""" Slang language server

"""

import std
from std import print, str_len
from httpclient import parse_header, Header
from utils import panic
from logging import log_debug
from listtype import List
from bytes import ByteArray, bytes_to_ascii
from json import parse_json, JsonException, JsonValue, json_to_string
from strlib import trim, str_to_int

pub fn main() -> int:
	loop:
		let request = recv_request()
		let response = JsonValue.Null() #"> "# {request.a}""
		send_response(response)
	0

fn read_line() -> str:
	let f = std.file_get_stdin()
	std.file_readln(handle: f)

fn read_n_as_str(n: int) -> str:
	let f = std.file_get_stdin()
	let ba = ByteArray()
	let buffer: [uint8] = [n : uint8]
	let res = std.file_read_n_bytes(handle: f, buffer, bufsize: n)
	if res == n:
		var i = 0
		while i < res:
			ba.append(int(buffer[i]))
			i += 1
	else:
		panic("Invalid read: {res} != {n}")
	bytes_to_ascii(data: ba.to_bytes())

fn recv_request() -> JsonValue:
	let headers: List[Header] = List()
	loop:
		let line = trim(read_line())
		# std.print("Line: '{line}'")
		if line == "":
			if headers.is_empty():
				continue
			else:
				break
		else:
			let header = parse_header(line)
			headers.append(header)
	var n = 0
	for header in headers:
		# print("header: '{header.name}'")
		if header.name == "Content-Length":
			n = str_to_int(header.value)
			# print("n = {n}")
		else:
			log_debug("Header not supported: {header.name}")
			pass

	if n == 0:
		log_debug("No content length!")
		return JsonValue.Null()
	let json_text = read_n_as_str(n)

	# print("req: {json_text}")
	try:
		let obj = parse_json(text: json_text)
		return obj
	except (ex: JsonException):
		panic("Json error: {ex.message}")
	panic("Should not get here!")


# struct Request:
#     obj: JsonValue

fn send_response(obj?: JsonValue):
	let json_text = json_to_string(obj)
	print("Content-Length: {str_len(text: json_text)}")
	print("")
	print(json_text)
