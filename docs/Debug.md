# Debug

Journalctl command to get all messages above info level from current boot, in reverse order (newest first).

```sh
journalctl -b -p warning -r --no-pager
```
