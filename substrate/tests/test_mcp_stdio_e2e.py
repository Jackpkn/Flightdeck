"""End-to-end integration test for ECS MCP stdio protocol."""

import json
import subprocess
import sys
from pathlib import Path


def test_mcp_server_stdio_end_to_end():
    """Spawns ecs serve via subprocess and communicates over stdio using JSON-RPC."""
    src_dir = str(Path(__file__).parent.parent / "src")

    import tempfile
    import os
    tmp_dir = tempfile.mkdtemp()
    env = dict(os.environ)
    env["FLIGHTDECK_ECS_DB"] = str(Path(tmp_dir) / "test_mcp.sqlite")

    proc = subprocess.Popen(
        [sys.executable, "-m", "ecs.server"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        cwd=src_dir,
        env=env,
        text=True,
    )

    try:
        # 1. Initialize
        init_req = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": {"name": "claude-code", "version": "1.0.0"},
            },
        }
        proc.stdin.write(json.dumps(init_req) + "\n")
        proc.stdin.flush()

        line = proc.stdout.readline()
        assert line, "No response from MCP server on initialize"
        init_res = json.loads(line)
        assert init_res.get("id") == 1
        assert "serverInfo" in init_res.get("result", {})
        assert init_res["result"]["serverInfo"]["name"] == "flightdeck-ecs"

        # 2. Notifications initialized
        init_notif = {
            "jsonrpc": "2.0",
            "method": "notifications/initialized",
            "params": {},
        }
        proc.stdin.write(json.dumps(init_notif) + "\n")
        proc.stdin.flush()

        # 3. List tools
        tools_req = {
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/list",
            "params": {},
        }
        proc.stdin.write(json.dumps(tools_req) + "\n")
        proc.stdin.flush()

        line = proc.stdout.readline()
        assert line, "No response from MCP server on tools/list"
        tools_res = json.loads(line)
        assert tools_res.get("id") == 2
        tool_names = [t["name"] for t in tools_res["result"]["tools"]]
        assert "memory_context" in tool_names
        assert "memory_store" in tool_names
        assert "memory_adjudicate" in tool_names
        assert "memory_pending_adjudication" in tool_names
        assert "memory_resolve" in tool_names
        assert "memory_dream" in tool_names

        # 4. Call memory_store in Process A (Session 1)
        store_call = {
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": {
                "name": "memory_store",
                "arguments": {
                    "project": "Flightdeck",
                    "file_path": "Sources/Flightdeck/DevCleaner.swift",
                    "kind": "trap",
                    "authority": "L1",
                    "trigger_pattern": ".measured",
                    "failure_signature": "type ContextWindowSource has no member 'measured'",
                    "resolution": "Valid cases are .statusline, .inferred, .fallback",
                },
            },
        }
        proc.stdin.write(json.dumps(store_call) + "\n")
        proc.stdin.flush()

        line = proc.stdout.readline()
        assert line, "No response from MCP server on memory_store"
        store_res = json.loads(line)
        assert store_res.get("id") == 3
        content = store_res["result"]["content"][0]["text"]
        assert "stored_atom_id" in content
        assert "active" in content

    finally:
        # Terminate Process A (Session 1 completes / exits)
        proc.terminate()
        proc.wait(timeout=2)

    # ---------------------------------------------------------
    # Process B (Session 2): Fresh subprocess on cold database
    # ---------------------------------------------------------
    proc_b = subprocess.Popen(
        [sys.executable, "-m", "ecs.server"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        cwd=src_dir,
        env=env,
        text=True,
    )

    try:
        # Handshake with Process B
        proc_b.stdin.write(json.dumps(init_req) + "\n")
        proc_b.stdin.flush()
        line_b = proc_b.stdout.readline()
        assert line_b, "No response from fresh MCP server (Process B) on initialize"
        assert json.loads(line_b).get("id") == 1

        proc_b.stdin.write(json.dumps(init_notif) + "\n")
        proc_b.stdin.flush()

        # Call memory_context in Process B (Session 2 cold-start retrieval)
        context_call = {
            "jsonrpc": "2.0",
            "id": 4,
            "method": "tools/call",
            "params": {
                "name": "memory_context",
                "arguments": {
                    "project": "Flightdeck",
                    "file_paths": ["Sources/Flightdeck/DevCleaner.swift"],
                    "intent": "cleaner measured",
                },
            },
        }
        proc_b.stdin.write(json.dumps(context_call) + "\n")
        proc_b.stdin.flush()

        line_b = proc_b.stdout.readline()
        assert line_b, "No response from fresh MCP server on memory_context"
        context_res = json.loads(line_b)
        assert context_res.get("id") == 4
        text_out = context_res["result"]["content"][0]["text"]
        assert "TRAP" in text_out
        assert "DevCleaner.swift" in text_out
        assert "Valid cases are .statusline, .inferred, .fallback" in text_out

        print("✅ Cross-Process MCP Stdio Restart test PASSED (Session 1 write -> Session 2 cold-start read)")

    finally:
        proc_b.terminate()
        proc_b.wait(timeout=2)


if __name__ == "__main__":
    test_mcp_server_stdio_end_to_end()
