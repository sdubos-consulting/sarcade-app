"""Prints the --dart-define of the Firebase wake-up, one per line, from a
google-services.json (same values as the former GitHub CI step).

    python -I tool/fcm_defines.py C:\\dev\\secrets\\android\\google-services.json
"""
import json
import sys

PACKAGE = "org.sarcade.sarcade_app"


def defines(g: dict) -> list[str]:
    c = next(c for c in g["client"] if c["client_info"]["android_client_info"]["package_name"] == PACKAGE)
    return [
        "--dart-define=SARCADE_FCM_API_KEY=" + c["api_key"][0]["current_key"],
        "--dart-define=SARCADE_FCM_APP_ID=" + c["client_info"]["mobilesdk_app_id"],
        "--dart-define=SARCADE_FCM_SENDER_ID=" + g["project_info"]["project_number"],
        "--dart-define=SARCADE_FCM_PROJECT_ID=" + g["project_info"]["project_id"],
    ]


if __name__ == "__main__":
    with open(sys.argv[1], encoding="utf-8") as f:
        print("\n".join(defines(json.load(f))))
