#!/usr/bin/env python

import json
import logging
import os
import sys

import setproctitle
from libinput import ContextType, EventType, KeyState, LibInput


def mod_key_event(state):
    text = ""
    if state == KeyState.PRESSED:
        text = ""
    # elif state == KeyState.RELEASED:
    #     print("mod aka super released")

    data = {"text": text, "alt": "mod-key", "class": "custom-mod-key"}
    sys.stdout.write(json.dumps(data) + "\n")
    sys.stdout.flush()


if __name__ == "__main__":
    logger = logging.getLogger(__name__)
    # Kill other instances
    os.system("pkill --exact mod-key.py")
    # Set process title
    setproctitle.setproctitle("mod-key.py")
    while True:
        try:
            li = LibInput(context_type=ContextType.UDEV)
            li.assign_seat("seat0")
            for event in li.events:
                if event.type == EventType.KEYBOARD_KEY:
                    # print(event.key, event.key_state)
                    if event.key == 125:
                        mod_key_event(event.key_state)
        except Exception as e:
            logger.error(e)
