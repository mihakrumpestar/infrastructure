# Disk

## Info

```sh
lsblk -o type,name,label,partlabel # Disks and partlabels

df -h # Disk usage
lsblk # Mount points

ncdu / --exclude /media
```

## Modify

```sh
mkfs.xfs -f -L MYLABEL /dev/sdX1
```

```sh
parted <block device> print
parted <block device> name <partition> <partlabel>
```

## Drive test

Sequential READ speed with big blocks QD32 (this should be near the number you see in the specifications for your drive):

```sh
fio --name TEST --eta-newline=5s --filename=fio-tempfile.dat --rw=read --size=500m --io_size=10g --blocksize=1024k --ioengine=libaio --fsync=10000 --iodepth=32 --direct=1 --numjobs=1 --runtime=60 --group_reporting
```

Sequential WRITE speed with big blocks QD32 (this should be near the number you see in the specifications for your drive):

```sh
fio --name TEST --eta-newline=5s --filename=fio-tempfile.dat --rw=write --size=500m --io_size=10g --blocksize=1024k --ioengine=libaio --fsync=10000 --iodepth=32 --direct=1 --numjobs=1 --runtime=60 --group_reporting
```

Random 4K read QD1 (this is the number that really matters for real world performance unless you know better for sure):

```sh
fio --name TEST --eta-newline=5s --filename=fio-tempfile.dat --rw=randread --size=500m --io_size=10g --blocksize=4k --ioengine=libaio --fsync=1 --iodepth=1 --direct=1 --numjobs=1 --runtime=60 --group_reporting
```

Mixed random 4K read and write QD1 with sync (this is worst case performance you should ever expect from your drive, usually less than 1% of the numbers listed in the spec sheet):

```sh
fio --name TEST --eta-newline=5s --filename=fio-tempfile.dat --rw=randrw --size=500m --io_size=10g --blocksize=4k --ioengine=libaio --fsync=1 --iodepth=1 --direct=1 --numjobs=1 --runtime=60 --group_reporting
```
