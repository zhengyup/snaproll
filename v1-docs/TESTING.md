# MVP Testing Checklist

- Can create event
- Can join event locally
- Can open camera
- Can take photo
- Photo is saved
- Photo is not visible before unlock
- Shot count decreases
- Cannot exceed shot limit
- Album reveals after unlock time
- App restart preserves event/photo state
- Airplane mode does not lose photos

## Snaproll Export Checklist

- Can export one revealed photo to Apple Photos
- Can export an entire revealed roll to Apple Photos
- Exported photos appear in Apple Photos
- Export attempts follow capture order
- Exported photos preserve the rendered film look
- Export still works after restarting the app
- Permission denial is handled gracefully
- Limited library access still allows export
- A failed photo does not stop the rest of a whole-roll export
- Can open the native iOS share sheet for a revealed photo
- Can open the native iOS share sheet for a revealed roll
- Exporting does not remove photos stored inside Snaproll
- No crashes during export or share flows
