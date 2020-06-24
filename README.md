# Chroot with a fake root user

This script creates a fake root where your user has write permission to arbitrary locations. It does not require any dependencies.

## Why do it?

I wrote this when I had to download and extract a Linux package and run it as a non-root user. Trouble was the package was dynamically loading its shared libraries from `/usr/lib64`, ignoring the `LD_LIBRARY_PATH` variable. So the only way I could run it was inside a chroot where I could copy its libraries to the system location. But of course to create a functioning chroot you need to do one of the following things:

* Copy over most directories, such as `/etc`, `/dev` and others to the new fake root...
	
	Not efficient, would take a lot of space and probably fail for `/dev`, `/proc` and `/sys`.
	
* Mount an overlay filesystem into the fake root

	Ideal solution, except... it requires `root`
	
* Bind mount most directories

	Good, but again it requires root... or so I thought!
	
	Turns out, in **some** cases [you can trick mount into thinking you're root](https://mostlyuseful.tech/posts/overlay-mounting/). The article I'm linking to suggests it should work with overlay filesystems, but at least on Amazon Linux it doesn't: it still fails with permission error. However, it works with bind mounts. So I wrote this script.
	
## What it does

It takes a list of directories or files which you want to be writable to your fake `root` user inside your fake root directory, and bind mounts everything else (for files it creates hard links).

For example if you want a fake root where your fake `root` user has write access to `/usr/bin`, `/usr/lib64` and `/etc/hosts`, call the script with:

```
fake-root-chroot.sh -w /etc/hosts /usr/lib64 /usr/bin -r /path/to/chroot
```

The script will create the following structure:

`/etc ->` a new directory owned by the fake `root` user

`/etc/hosts ->` a copy of the original `/etc/hosts`, now owned by the fake `root` user

`/etc/* ->` all directories are bind-mounted, all other files are hard-symlinked

`/usr/bin ->` same as for `/etc`

`/* ->` all directories are bind-mounted, all files are hard-symlinked 
