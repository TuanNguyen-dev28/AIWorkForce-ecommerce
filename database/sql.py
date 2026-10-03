"""Split MySQL scripts, including DELIMITER blocks, without rewriting their SQL."""

import re


def split_sql(source: str) -> list[str]:
    delimiter = ";"
    result: list[str] = []
    buffer: list[str] = []
    quote: str | None = None
    comment = False
    for line in source.splitlines(keepends=True):
        directive = re.fullmatch(r"\s*DELIMITER\s+(\S+)\s*", line, re.IGNORECASE)
        if directive and quote is None and not comment:
            if "".join(buffer).strip():
                raise ValueError("DELIMITER changed inside an unfinished statement")
            delimiter = directive[1]
            continue
        index = 0
        while index < len(line):
            char = line[index]
            following = line[index : index + 2]
            if comment:
                if following == "*/":
                    comment = False
                    buffer.append(" ")
                    index += 2
                else:
                    index += 1
                continue
            if quote:
                buffer.append(char)
                if char == "\\" and quote != "`" and index + 1 < len(line):
                    buffer.append(line[index + 1])
                    index += 2
                    continue
                if char == quote:
                    if index + 1 < len(line) and line[index + 1] == quote:
                        buffer.append(line[index + 1])
                        index += 2
                        continue
                    quote = None
                index += 1
                continue
            if following == "/*":
                # Executable version comments require a dedicated parser. Fail closed.
                if line[index : index + 3] == "/*!":
                    raise ValueError("Executable MySQL comments are not supported")
                comment = True
                index += 2
                continue
            if char == "#" or (following == "--" and line[index + 2 : index + 3].isspace()):
                buffer.append("\n")
                break
            if char in {"'", '"', "`"}:
                quote = char
            if line.startswith(delimiter, index):
                statement = "".join(buffer).strip()
                if statement:
                    result.append(statement)
                buffer = []
                index += len(delimiter)
            else:
                buffer.append(char)
                index += 1
    if quote or comment or "".join(buffer).strip():
        raise ValueError("Unterminated SQL statement, string or comment")
    return result
