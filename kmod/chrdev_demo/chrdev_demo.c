// SPDX-License-Identifier: GPL-2.0
/*
 * chrdev_demo - minimal character device driver
 *
 * Exposes /dev/chrdev_demo backed by a small in-kernel buffer.
 * Supports open / release / read / write / llseek with proper
 * concurrency protection.
 *
 * Build (on the board, or against a kernel source tree):
 *   make -C /lib/modules/$(uname -r)/build M=$PWD modules
 * Load:
 *   sudo insmod chrdev_demo.ko
 *   ls -l /dev/chrdev_demo
 *   echo hello > /dev/chrdev_demo
 *   cat /dev/chrdev_demo
 * Unload:
 *   sudo rmmod chrdev_demo
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/uaccess.h>
#include <linux/mutex.h>
#include <linux/slab.h>
#include <linux/version.h>

#define DRV_NAME    "chrdev_demo"
#define DRV_CLASS   "chrdev_demo_class"
#define BUF_SIZE    1024

struct chrdev_demo {
	struct cdev   cdev;
	dev_t         devt;
	struct class *class;
	struct device *device;
	char         *buf;
	size_t        data_len;   /* valid bytes currently in buf */
	struct mutex  lock;       /* protects buf + data_len       */
};

static struct chrdev_demo *gdev;

/* ---------- file_operations ---------- */

static int chrdev_demo_open(struct inode *inode, struct file *filp)
{
	struct chrdev_demo *dev =
		container_of(inode->i_cdev, struct chrdev_demo, cdev);

	filp->private_data = dev;
	pr_info(DRV_NAME ": open by pid=%d\n", current->pid);
	return 0;
}

static int chrdev_demo_release(struct inode *inode, struct file *filp)
{
	pr_info(DRV_NAME ": release by pid=%d\n", current->pid);
	return 0;
}

static ssize_t chrdev_demo_read(struct file *filp, char __user *ubuf,
				size_t count, loff_t *ppos)
{
	struct chrdev_demo *dev = filp->private_data;
	ssize_t ret;

	if (mutex_lock_interruptible(&dev->lock))
		return -ERESTARTSYS;

	if (*ppos >= dev->data_len) {     /* EOF */
		ret = 0;
		goto out;
	}
	if (*ppos + count > dev->data_len)
		count = dev->data_len - *ppos;

	if (copy_to_user(ubuf, dev->buf + *ppos, count)) {
		ret = -EFAULT;
		goto out;
	}
	*ppos += count;
	ret    = count;

out:
	mutex_unlock(&dev->lock);
	return ret;
}

static ssize_t chrdev_demo_write(struct file *filp, const char __user *ubuf,
				 size_t count, loff_t *ppos)
{
	struct chrdev_demo *dev = filp->private_data;
	ssize_t ret;

	if (*ppos >= BUF_SIZE)
		return -ENOSPC;
	if (*ppos + count > BUF_SIZE)
		count = BUF_SIZE - *ppos;

	if (mutex_lock_interruptible(&dev->lock))
		return -ERESTARTSYS;

	if (copy_from_user(dev->buf + *ppos, ubuf, count)) {
		ret = -EFAULT;
		goto out;
	}
	*ppos += count;
	if (*ppos > dev->data_len)
		dev->data_len = *ppos;
	ret = count;

out:
	mutex_unlock(&dev->lock);
	return ret;
}

static loff_t chrdev_demo_llseek(struct file *filp, loff_t off, int whence)
{
	struct chrdev_demo *dev = filp->private_data;
	loff_t newpos;

	switch (whence) {
	case SEEK_SET: newpos = off;                 break;
	case SEEK_CUR: newpos = filp->f_pos + off;   break;
	case SEEK_END: newpos = dev->data_len + off; break;
	default:       return -EINVAL;
	}
	if (newpos < 0 || newpos > BUF_SIZE)
		return -EINVAL;

	filp->f_pos = newpos;
	return newpos;
}

static const struct file_operations chrdev_demo_fops = {
	.owner   = THIS_MODULE,
	.open    = chrdev_demo_open,
	.release = chrdev_demo_release,
	.read    = chrdev_demo_read,
	.write   = chrdev_demo_write,
	.llseek  = chrdev_demo_llseek,
};

/* ---------- module init / exit ---------- */

static int __init chrdev_demo_init(void)
{
	int ret;

	gdev = kzalloc(sizeof(*gdev), GFP_KERNEL);
	if (!gdev)
		return -ENOMEM;

	gdev->buf = kzalloc(BUF_SIZE, GFP_KERNEL);
	if (!gdev->buf) {
		ret = -ENOMEM;
		goto err_free_dev;
	}
	mutex_init(&gdev->lock);

	/* 1. Reserve a dynamic major number, 1 minor */
	ret = alloc_chrdev_region(&gdev->devt, 0, 1, DRV_NAME);
	if (ret)
		goto err_free_buf;

	/* 2. Register cdev with the VFS */
	cdev_init(&gdev->cdev, &chrdev_demo_fops);
	gdev->cdev.owner = THIS_MODULE;
	ret = cdev_add(&gdev->cdev, gdev->devt, 1);
	if (ret)
		goto err_unregister;

	/* 3. Create /sys/class entry so udev auto-creates /dev/chrdev_demo */
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 4, 0)
	gdev->class = class_create(DRV_CLASS);
#else
	gdev->class = class_create(THIS_MODULE, DRV_CLASS);
#endif
	if (IS_ERR(gdev->class)) {
		ret = PTR_ERR(gdev->class);
		goto err_cdev_del;
	}

	gdev->device = device_create(gdev->class, NULL, gdev->devt,
				     NULL, DRV_NAME);
	if (IS_ERR(gdev->device)) {
		ret = PTR_ERR(gdev->device);
		goto err_class_destroy;
	}

	pr_info(DRV_NAME ": loaded, major=%d minor=%d  -> /dev/%s\n",
		MAJOR(gdev->devt), MINOR(gdev->devt), DRV_NAME);
	return 0;

err_class_destroy:
	class_destroy(gdev->class);
err_cdev_del:
	cdev_del(&gdev->cdev);
err_unregister:
	unregister_chrdev_region(gdev->devt, 1);
err_free_buf:
	kfree(gdev->buf);
err_free_dev:
	kfree(gdev);
	return ret;
}

static void __exit chrdev_demo_exit(void)
{
	device_destroy(gdev->class, gdev->devt);
	class_destroy(gdev->class);
	cdev_del(&gdev->cdev);
	unregister_chrdev_region(gdev->devt, 1);
	kfree(gdev->buf);
	kfree(gdev);
	pr_info(DRV_NAME ": unloaded\n");
}

module_init(chrdev_demo_init);
module_exit(chrdev_demo_exit);

MODULE_LICENSE("GPL v2");
MODULE_AUTHOR("ming");
MODULE_DESCRIPTION("Minimal character device driver demo");
MODULE_VERSION("0.1");
