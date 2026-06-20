# AI Disclosure

This project was developed with significant assistance from **Claude** (by Anthropic),
an AI assistant.

## What the AI helped with

- Porting the original Groovy Device Handler to the SmartThings Edge (Lua) architecture
- Debugging Zigbee binding issues (discovering that `build_bind_request` needed
  fallback approaches for the hub EUI)
- Fixing ZCL command body parsing (the SDK parses commands into named fields,
  not raw `body_bytes`)
- Implementing millisecond-precision knob timing using `socket.gettime()`
- Writing the SmartThings Rules API JSON for the Sonos integration
- Fixing the `then`-inside-`if` structure required by the Rules API
- Creating this README and repository structure

## What the human did

- Identified the original project and goal
- Tested every iteration on real hardware (IKEA SYMFONISK + SmartThings Hub + Sonos)
- Provided logcat output and screenshots at each debugging step
- Made all final decisions about features and scope

## Note

All code has been reviewed and tested on real hardware before being published.
AI-generated code can contain mistakes — if you find a bug, please open an issue.
