"""Translate Android ip output into the iproute2 JSON used by our helpers."""

import ipaddress
import json
import os
import re
import shlex
import subprocess
import sys


DENIED = {
    "Cannot bind netlink socket: Permission denied",
    "Cannot open netlink socket: Permission denied",
}
ROUTE_TYPES = {
    "unicast", "local", "broadcast", "multicast", "anycast", "unreachable",
    "prohibit", "blackhole", "throw", "nat",
}
ROUTE_FIELDS = {
    "via": "gateway", "dev": "dev", "src": "prefsrc", "proto": "protocol",
    "scope": "scope", "table": "table", "metric": "metric", "uid": "uid",
    "pref": "pref", "hoplimit": "hoplimit", "mtu": "mtu",
}


def number(value):
    return int(value) if value.isdecimal() else value


def fields(tokens, names):
    values = {}
    cursor = iter(tokens)
    for key in cursor:
        if key in names:
            value = next(cursor, "")
            if value:
                values[names[key]] = number(value)
    return values


def routes(lines):
    output = []
    for line in lines:
        destination, *tokens = line.split()
        if destination in ROUTE_TYPES and tokens:
            kind, destination, *tokens = destination, *tokens
        else:
            kind = None
        if destination != "default":
            try:
                ipaddress.ip_network(destination, strict=False)
            except ValueError:
                continue
        route = {"dst": destination, **fields(tokens, ROUTE_FIELDS)}
        if kind is not None:
            route["type"] = kind
        if "onlink" in tokens:
            route["flags"] = ["onlink"]
        output.append(route)
    return output


def addresses(lines):
    interfaces = []
    for line in lines:
        header = re.match(r"^(\d+): ([^:]+): <([^>]*)>\s*(.*)", line)
        if header:
            index, name, flags, attrs = header.groups()
            interface = {
                "ifindex": int(index),
                "ifname": name.split("@", 1)[0],
                "flags": flags.split(",") if flags else [],
                **fields(attrs.split(), {key: key for key in ("mtu", "qdisc", "group", "qlen")}),
                "addr_info": [],
            }
            state = fields(attrs.split(), {"state": "operstate"})
            interface.update(state)
            interfaces.append(interface)
            continue
        if not interfaces:
            continue
        tokens = line.split()
        if tokens[0].startswith("link/"):
            interface["link_type"] = tokens[0].removeprefix("link/")
            if len(tokens) > 1:
                interface["address"] = tokens[1]
            interface.update(fields(tokens[2:], {"brd": "broadcast"}))
        elif tokens[0] in {"inet", "inet6"} and len(tokens) > 1:
            family, address, *attrs = tokens
            number_and_prefix = ipaddress.ip_interface(address)
            interface["addr_info"].append({
                "family": family,
                "local": str(number_and_prefix.ip),
                "prefixlen": number_and_prefix.network.prefixlen,
                **fields(attrs, {"scope": "scope", "brd": "broadcast", "peer": "peer"}),
            })
    return interfaces


def neighbours(lines):
    output = []
    states = {"INCOMPLETE", "REACHABLE", "STALE", "DELAY", "PROBE", "FAILED", "NOARP", "PERMANENT"}
    for line in lines:
        destination, *tokens = line.split()
        try:
            ipaddress.ip_address(destination)
        except ValueError:
            continue
        result = {"dst": destination, **fields(tokens, {"dev": "dev", "lladdr": "lladdr", "probes": "probes"})}
        if "router" in tokens:
            result["router"] = True
        result["state"] = [token for token in tokens if token in states]
        output.append(result)
    return output


def android(command, args):
    program = "exec " + shlex.join(["/system/bin/ip", *args]) + " 2>&1"
    # Some Shizuku versions relay parts of the same dump to stderr.
    result = subprocess.run([*command, program], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    result.stdout = result.stdout.removeprefix("Entering shell...\n")
    return result


def default_routes(command, families, interface):
    for family in families:
        destination = "192.0.2.1" if family == "-4" else "2001:db8::1"
        result = android(command, [family, "route", "get", destination])
        selected = routes(result.stdout.splitlines()) if result.returncode == 0 else []
        if not selected:
            continue
        route = selected[0]
        if interface and route.get("dev") != interface:
            continue
        table = str(route.get("table", "main"))
        result = android(command, [family, "route", "show", "table", table, "default"])
        if result.returncode == 0:
            yield from (
                default for default in routes(result.stdout.splitlines())
                if default["dst"] == "default" and default.get("dev") == route.get("dev")
                and default.get("gateway") == route.get("gateway")
            )


def query(command, arguments):
    flags_end = next((i for i, arg in enumerate(arguments) if not arg.startswith("-")), len(arguments))
    flags, arguments = arguments[:flags_end], arguments[flags_end:]
    family = [flag for flag in flags if flag in {"-4", "-6"}]
    kind, *query_args = arguments
    if "address".startswith(kind):
        parser = addresses
    elif "route".startswith(kind):
        parser = routes
    elif "neighbour".startswith(kind) or "neighbor".startswith(kind):
        parser = neighbours
    else:
        return None
    result = android(command, [*family, *arguments])
    if result.returncode:
        sys.stderr.write(result.stdout)
        return result.returncode
    output = parser([line for line in result.stdout.splitlines() if line.strip()])
    if parser is routes and (not query_args or "show".startswith(query_args[0]) or "list".startswith(query_args[0])):
        filters = query_args[1:]
        if filters[:1] == ["default"]:
            filters = filters[1:]
        if not filters or (len(filters) == 2 and filters[0] == "dev"):
            active = default_routes(command, family or ["-4"], filters[1] if filters else None)
            # Main-table defaults already have native metrics and need no replacement.
            for default in active:
                if not any(
                    entry["dst"] == "default" and entry.get("gateway") == default.get("gateway")
                    and entry.get("dev") == default.get("dev") for entry in output
                ):
                    output.append(default)
    print(json.dumps(output, indent=4 if set(flags) & {"-p", "-pretty", "--pretty"} else None))
    return 0


def main():
    native, *args = sys.argv[1:]
    separator = args.index("--")
    command, args = args[:separator], args[separator + 1:]
    result = subprocess.run([native, *args], capture_output=True, text=True, env={**os.environ, "LC_ALL": "C"})
    if result.returncode and result.stderr.strip() in DENIED:
        status = query(command, args)
        if status is not None:
            return status
    sys.stdout.write(result.stdout)
    sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
