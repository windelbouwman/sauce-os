
from utils import unimplemented, log_info, log_debug, assert
from std import str_len, str_to_int
from datatypes import List
from strlib import split_string
from urlparse import parse_url


fn get(url: str) -> str:
    """ Get data from an url """
    let client = HttpClient()
    return client.get(url)

fn post(url: str):
    """ Post to an url """
    let client = HttpClient()
    client.post(url)

class HttpClient:
    """ HTTP client """
    var s: int = 0 # socket handle

    fn connect():
        unimplemented("connect")
    
    fn disconnect():
        unimplemented("disconnect")

    fn get(url: str) -> str:
        log_info("GET {url}")
        let parsed_url = parse_url(url)
        # let s = socket()
        # s.connect(parsed_url.host, port: 80)

        # Request
        let request: List[str] = List()
        request.append("GET {parsed_url.path} HTTP/1.0")
        request.append("Host: {parsed_url.host}")
        request.append("")
        write_lines(lines: request)

        # Response
        let status_line = read_line()
        let parts = split_string(text: status_line, sep: ' ')
        assert(condition: parts.len() == 3, message: "status line must contain three values separated by spaces.")
        let version = parts[0]
        let status = str_to_int(parts[1])
        let explanation = parts[2]

        loop:
            let line = read_line()
            if str_len(text: line) == 0:
                break
            let header = parse_header(line)

        # Content
        let content = read()
        return content

    fn post(url: str):
        unimplemented("POST")

    fn write_lines(lines: List[str]):
        for line in lines:
            write_line(line)

    fn write_line(line: str):
        unimplemented("write_line")
        # s.send((line + "\r\n").encode("ascii"))

    fn read_line() -> str:
        unimplemented("readline")

    fn read() -> str:
        unimplemented("read")

fn parse_header(line: str) -> Header:
    let parts = split_string(text: line, sep: ':')
    assert(condition: parts.len() == 2, message: "header line must contain a single ':' ")
    let name = parts[0]
    let value = parts[0]
    return Header(name, value)

struct Header:
    name: str
    value: str
