
FROM alpine:3.23 AS builder

RUN apk add --no-cache build-base
RUN apk add --no-cache python3
RUN apk add --no-cache py3-lark-parser py3-networkx py3-pytest py3-rich

# Bootstrap compiler:
WORKDIR /src
COPY compiler1/ compiler1/
COPY Makefile bootstrap.py .
COPY Apps/ Apps/
COPY Libs/ Libs/
COPY --exclude=*.pyc runtime/ runtime/
RUN make build/slangrt.a
RUN make build/compiler5
RUN make all-apps-x86

# Clean slate
FROM alpine:3.23
WORKDIR /src
COPY --from=builder /src/build/x86 /src/build/x86
