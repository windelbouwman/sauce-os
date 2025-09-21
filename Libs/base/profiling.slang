"""
Application profiling
"""

import std
from listtype import List
import json

enum Event:
	Enter(name: str)
	Leave

struct TimedEvent:
	time: int
	event: Event

pub class Profiler:
	var m_events: List[TimedEvent] = List()

	pub fn enter(name: str):
		""" Enter a measured zone """
		add_event(Event.Enter(name))

	pub fn leave():
		add_event(Event.Leave())

	pub fn add_event(event?: Event):
		# TODO: add timestamp
		let time = std.get_time()
		m_events.append(TimedEvent(time, event))

	pub fn write_json(filename: str):
		""" Generate speedscope compatible json file """
		# Translate to speedscope frames:
		let events: List[SpeedscopeEvent] = List()
		let frames: List[SpeedscopeFrame] = List()
		let stack: List[str] = List()

		for event in m_events:
			case event.event:
				Enter(name):
					let frame = get_frame_index(name, frames)
					events.append(SpeedscopeEvent(typ: "O", at: event.time, frame))
					stack.prepend(name)
				Leave:
					let name = stack.pop_front()
					let frame = get_frame_index(name, frames)
					events.append(SpeedscopeEvent(typ: "C", at: event.time, frame))

		write_speedscope_json(filename, events, frames)

fn get_frame_index(name: str, frames: List[SpeedscopeFrame]) -> int:
	# TODO: potentially O(n) code:
	var index = 0
	for frame in frames:
		if frame.name == name:
			return index
		else:
			index += 1
	frames.append(SpeedscopeFrame(name, file: "", line: 1, col: 1))
	index

struct SpeedscopeEvent:
	typ: str
	at: int
	frame: int

struct SpeedscopeFrame:
	name: str
	file: str
	line: int
	col: int

fn write_speedscope_json(filename: str, events: List[SpeedscopeEvent], frames: List[SpeedscopeFrame]):
	var ser = json.JsonBuilder()
	ser.begin_object()
	ser.add_text_attribute(attr: "$schema", text: "https://www.speedscope.app/file-format-schema.json")

	ser.begin_array()  # profiles
	ser.begin_object()
	ser.add_text_attribute(attr: "type", text: "evented")
	ser.add_text_attribute(attr: "name", text: "python")
	ser.add_text_attribute(attr: "unit", text: "nanoseconds")
	ser.add_integer_attribute(attr: "startValue", value: events.first().at)
	ser.add_integer_attribute(attr: "endValue", value: events.last().at)
	ser.begin_array()  # events
	for event in events:
		ser.begin_object()
		ser.add_text_attribute(attr: "type", text: event.typ)
		ser.add_integer_attribute(attr: "at", value: event.at)
		ser.add_integer_attribute(attr: "frame", value: event.frame)
		ser.end_object_as_element()
	ser.end_array_as_attribute(attr: "events")
	ser.end_object_as_element()
	ser.end_array_as_attribute(attr: "profiles")

	ser.begin_object()  # shared
	ser.begin_array()  # frames
	for frame in frames:
		ser.begin_object()
		ser.add_text_attribute(attr: "name", text: frame.name)
		ser.add_text_attribute(attr: "file", text: frame.file)
		ser.add_integer_attribute(attr: "line", value: frame.line)
		ser.add_integer_attribute(attr: "col", value: frame.col)
		ser.end_object_as_element()
	ser.end_array_as_attribute(attr: "frames")
	ser.end_object_as_attribute(attr: "shared")

	ser.add_integer_attribute(attr: "activeProfileIndex", value: 0)
	ser.add_text_attribute(attr: "exporter", text: "slang profiler")
	ser.add_text_attribute(attr: "name", text: "a profile")

	let obj = ser.end_object()
	json.write_json_to_file(filename, obj)
