
from utils import assert
from strlib import split_string2, split_string

fn parse_url(url: str) -> ParsedUrl:
    """ Parse url into separate components.
    
    """
    let parts = split_string2(text: url, sep: "://")
    assert(condition: parts.len() == 2, message: "Url must contain a single '://' ")
    let scheme = parts[0]
    let parts2 = split_string(text: parts[1], sep: '/')

struct ParsedUrl:
    scheme: str
    host: str
    path: str
