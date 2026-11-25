#!/usr/bin/env python3
"""Local doubles for the Codex, Copilot and Pi launchers. No networking."""
import json
import os
from pathlib import Path
import re
import sys


def send(**message):
    print(json.dumps({"jsonrpc": "2.0", **message}), flush=True)


def request(method, params, request_id):
    send(method=method, params=params, id=request_id)
    answer = json.loads(sys.stdin.readline())
    assert answer["id"] == request_id, answer
    return answer


binary = Path(sys.argv[0]).name
codex = binary == "codex-acp"
pi = binary == "pi-acp"
for name in ("OPENAI_API_KEY", "CODEX_API_KEY", "DEFAULT_AUTH_REQUEST", "GH_TOKEN", "ANTHROPIC_API_KEY"):
    assert name not in os.environ
if binary == "pi":
    assert sys.argv[1:] == ["auth", "check", "--provider", "fixture", "--model", "fixture/start", "--json", "--no-refresh"]
    print(json.dumps({"provider": "fixture", "status": "ready", "authType": "oauth"}))
    sys.exit(0)
if pi:
    assert os.access(os.environ["PI_ACP_PI_COMMAND"], os.X_OK)
    assert os.environ["NVIM_AI_PI_MODEL"] == "fixture/start"
elif codex:
    config = json.loads(os.environ["CODEX_CONFIG"])
    assert config["model_provider"] == "openai"
    assert config["forced_login_method"] == "chatgpt"
    assert os.environ["INITIAL_AGENT_MODE"] == "read-only"
else:
    assert "--acp" in sys.argv and "--stdio" in sys.argv
    assert "--model" in sys.argv and "fixture-copilot" in sys.argv

session_number = 0
ask = False
startup = "pi v1.6.0\n---\n\n## Extensions\n- fixture\n"
for line in sys.stdin:
    msg = json.loads(line)
    method, params = msg.get("method"), msg.get("params") or {}
    if "id" not in msg:
        continue
    if method == "initialize":
        ask = params.get("clientCapabilities") == {}
        if pi:
            assert ask
        elif not codex and ask:
            assert "--deny-tool=*" in sys.argv
        result = {
            "protocolVersion": 1,
            "agentCapabilities": {},
            "authMethods": ([{"id": "api-key", "name": "API key"}]
                            + ([] if config.get("model") == "missing-chatgpt" else [{"id": "chat-gpt", "name": "ChatGPT"}])
                            if codex else []),
        }
    elif method == "authenticate":
        assert codex and config.get("model") != "missing-chatgpt" and params == {"methodId": "chat-gpt"}
        result = {}
    elif method == "session/new":
        session_number += 1
        if codex:
            # An explicit invalid model is silently replaced; the client must fail closed.
            model = config.get("model", "fixture-default")
            model = "fixture-default" if model == "unavailable" else model
            options = [
                {"id": "mode", "category": "mode", "type": "select", "currentValue": "read-only",
                 "options": [{"value": "read-only", "name": "Read only"}]},
                {"id": "model", "category": "model", "type": "select", "currentValue": model + "[medium]",
                 "options": [{"value": model + "[medium]", "name": model}]},
            ]
        elif pi:
            options = [{"id": "model", "category": "model", "type": "select", "currentValue": "fixture/start",
                        "options": [{"value": "fixture/start", "name": "Start"}]}]
        else:
            options = []
        result = {"sessionId": str(session_number), "configOptions": options}
        if pi:
            result["_meta"] = {"piAcp": {"startupInfo": startup}}
    elif method == "session/prompt":
        sid = params["sessionId"]
        prompt = "\n".join(block["text"] for block in params["prompt"] if block["type"] == "text")
        wrong_path = str(Path.cwd() / "never-write-me")
        denied = request("fs/write_text_file", {"sessionId": sid, "path": wrong_path, "content": "bad"}, 9100)
        assert "error" in denied
        if pi:
            assert "first unchanged" not in prompt and "last unchanged" not in prompt
            editing = "PI_EDIT_BEGIN" in prompt
            if editing:
                edit = json.loads(prompt.split("\n\n", 1)[1])
                assert edit["lines"] == ["middle and unselected"]
            else:
                assert "<selected_code>\nfi\nmi\n</selected_code>" in prompt
            reader = request("fs/read_text_file", {"sessionId": sid, "path": wrong_path}, 9101)
            assert "error" in reader
            permission = request("session/request_permission", {"sessionId": sid, "toolCall": {"kind": "edit"},
                                 "options": [{"optionId": "allow", "kind": "allow_once", "name": "Allow"}]}, 9102)
            assert permission["result"]["outcome"] == {"outcome": "cancelled"}
            if editing:
                response = {"delete": "[]", "malformed": "{}"}.get(edit["instruction"], '["PI CHANGED", "added line"]')
                chunks = [startup, f"PI_EDIT_BEGIN\n{response}\nPI_EDIT_END"]
            else:
                # Split the answer into realistic streamed chunks. Its first line
                # deliberately looks like a banner, but is not the metadata value.
                chunks = [startup, "pi v1.6.0\n", "Fixture block answer"]
            for chunk in chunks:
                send(method="session/update", params={"sessionId": sid, "update": {
                    "sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": chunk}}})
        elif ask:
            assert "<selected_code>\nmiddle\n</selected_code>" in prompt, prompt
            assert "first unchanged" not in prompt
            reader = request("fs/read_text_file", {"sessionId": sid, "path": wrong_path}, 9101)
            assert "error" in reader
            permission = request("session/request_permission", {"sessionId": sid, "toolCall": {"kind": "edit"},
                                 "options": [{"optionId": "allow", "kind": "allow_once", "name": "Allow"}]}, 9102)
            assert permission["result"]["outcome"] == {"outcome": "cancelled"}
            send(method="session/update", params={"sessionId": sid, "update": {
                "sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": "Fixture answer"}}})
        else:
            copy = re.search(r"editing `([^`]+)`", prompt).group(1)
            assert "adapter=openai #{chat}" in prompt
            assert "only edit lines 2-2" in prompt
            allowed = request("fs/write_text_file", {"sessionId": sid, "path": copy,
                              "content": "first changed outside\nMIDDLE CHANGED\nlast changed outside\n"}, 9103)
            assert "result" in allowed, allowed
        result = {"stopReason": "end_turn"}
    else:
        raise AssertionError(method)
    send(id=msg["id"], result=result)
