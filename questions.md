- wat is het verschil tussen class en struct? alleen methods en pub/priv zoals c++?
- En enum? methods op enum zou cool zijn


```python
class Rand
	...
	fn float() -> float:
```

Geeft "error: Not a type: function:float"

----

```python
class Rand:
	pub var seed: uint64 = 0
```

Geeft error zonder genoeg info

```
ERROR @ 76762000: Errors found during compilation
error: Got Int64, expected Uint64
```

moet

```python
class Rand:
	pub var state: uint64 = uint64(0)
```

zijn
