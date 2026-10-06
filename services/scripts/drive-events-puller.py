"""Pull Google Drive events from Pub/Sub and poke a trigger file.

Every event (file created/moved/changed in the watched folder) is acked and
coalesced: once no new event has arrived for DEBOUNCE seconds the trigger file
is touched, which fires a systemd path unit.
"""

import os
import pathlib
import sys
import threading
import time

from google.cloud import pubsub_v1

project = os.environ["DRIVE_EVENTS_PROJECT"]
subscription = os.environ["DRIVE_EVENTS_SUBSCRIPTION"]
trigger = pathlib.Path(os.environ["DRIVE_EVENTS_TRIGGER_FILE"])
debounce = float(os.environ.get("DRIVE_EVENTS_DEBOUNCE_SECONDS", "3"))

lock = threading.Lock()
last_event = 0.0
pending = False


def log(msg):
    print(msg, flush=True)


def on_message(message):
    global last_event, pending
    message.ack()
    attrs = message.attributes
    log(f"event {attrs.get('ce-type', '?')} {attrs.get('ce-subject', '?')}")
    with lock:
        last_event = time.monotonic()
        pending = True


def debouncer():
    global pending
    while True:
        time.sleep(0.5)
        with lock:
            fire = pending and time.monotonic() - last_event >= debounce
            if fire:
                pending = False
        if fire:
            trigger.write_text(f"{time.time()}\n")
            log("trigger touched")


def main():
    threading.Thread(target=debouncer, daemon=True).start()
    client = pubsub_v1.SubscriberClient()
    path = client.subscription_path(project, subscription)
    log(f"listening on {subscription}")
    with client:
        future = client.subscribe(path, callback=on_message)
        try:
            future.result()
        except Exception as exc:
            future.cancel()
            log(f"streaming pull failed: {exc!r}")
            sys.exit(1)


main()
