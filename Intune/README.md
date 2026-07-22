# OSD Cloud

## USB Disk
If the USB drive is formatted as GPT instead of MBR, it will not boot on many systems.
To fix this, use DiskPart to clean and convert the USB drive.

```shell
DISKPART
list disk
select disk <disknumber>
CLEAN
convert MBR
```
