/*
 * user-led control demo for STM32MP157
 *
 * Drives /sys/class/leds/user-led via the standard Linux LED sysfs class.
 *
 *   led on                       — full brightness
 *   led off                      — brightness 0
 *   led set <0..max>             — arbitrary brightness
 *   led blink [count] [ms]       — software blink, default 10x at 200ms
 *   led timer [on_ms] [off_ms]   — kernel `timer` trigger, runs until stopped
 *   led none                     — stop kernel trigger, back to manual mode
 *
 * Ctrl-C during `blink` leaves the LED off cleanly.
 */
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define LED_DIR "/sys/class/leds/user-led"

static volatile sig_atomic_t g_stop = 0;

static void on_sigint(int sig) {
    (void)sig;
    g_stop = 1;
}

/* Write a string to a sysfs attribute under LED_DIR. */
static int sysfs_write(const char *attr, const char *value) {
    char path[256];
    snprintf(path, sizeof(path), "%s/%s", LED_DIR, attr);
    FILE *f = fopen(path, "w");
    if (!f) {
        fprintf(stderr, "open %s: %s\n", path, strerror(errno));
        return -1;
    }
    int rc = fputs(value, f);
    fclose(f);
    if (rc == EOF) {
        fprintf(stderr, "write %s: %s\n", path, strerror(errno));
        return -1;
    }
    return 0;
}

static int sysfs_read_int(const char *attr, int *out) {
    char path[256];
    snprintf(path, sizeof(path), "%s/%s", LED_DIR, attr);
    FILE *f = fopen(path, "r");
    if (!f) {
        fprintf(stderr, "open %s: %s\n", path, strerror(errno));
        return -1;
    }
    int rc = fscanf(f, "%d", out);
    fclose(f);
    return rc == 1 ? 0 : -1;
}

static int set_brightness(int v) {
    char buf[16];
    snprintf(buf, sizeof(buf), "%d", v);
    return sysfs_write("brightness", buf);
}

static int ensure_no_trigger(void) {
    /* Required before manual brightness writes when a trigger is active. */
    return sysfs_write("trigger", "none");
}

static void sleep_ms(int ms) {
    struct timespec ts = { ms / 1000, (long)(ms % 1000) * 1000000L };
    nanosleep(&ts, NULL);
}

static void usage(const char *prog) {
    fprintf(stderr,
        "usage: %s on|off|set <n>|blink [count] [ms]|timer [on_ms] [off_ms]|none\n",
        prog);
}

int main(int argc, char **argv) {
    if (argc < 2) { usage(argv[0]); return 2; }

    int max = 255;
    sysfs_read_int("max_brightness", &max);

    const char *cmd = argv[1];

    if (!strcmp(cmd, "on")) {
        if (ensure_no_trigger()) return 1;
        return set_brightness(max) ? 1 : 0;
    }

    if (!strcmp(cmd, "off")) {
        if (ensure_no_trigger()) return 1;
        return set_brightness(0) ? 1 : 0;
    }

    if (!strcmp(cmd, "set")) {
        if (argc < 3) { usage(argv[0]); return 2; }
        int v = atoi(argv[2]);
        if (v < 0) v = 0;
        if (v > max) v = max;
        if (ensure_no_trigger()) return 1;
        return set_brightness(v) ? 1 : 0;
    }

    if (!strcmp(cmd, "blink")) {
        int count = (argc >= 3) ? atoi(argv[2]) : 10;
        int ms    = (argc >= 4) ? atoi(argv[3]) : 200;
        if (ensure_no_trigger()) return 1;
        signal(SIGINT, on_sigint);
        printf("blinking %d times, %d ms half-period (Ctrl-C to stop)\n",
               count, ms);
        for (int i = 0; i < count && !g_stop; i++) {
            set_brightness(max); sleep_ms(ms);
            if (g_stop) break;
            set_brightness(0);   sleep_ms(ms);
        }
        set_brightness(0);
        return 0;
    }

    if (!strcmp(cmd, "timer")) {
        int on_ms  = (argc >= 3) ? atoi(argv[2]) : 500;
        int off_ms = (argc >= 4) ? atoi(argv[3]) : 500;
        char buf[16];
        if (sysfs_write("trigger", "timer")) return 1;
        /* delay_on / delay_off only exist after the timer trigger is bound. */
        snprintf(buf, sizeof(buf), "%d", on_ms);
        if (sysfs_write("delay_on",  buf)) return 1;
        snprintf(buf, sizeof(buf), "%d", off_ms);
        if (sysfs_write("delay_off", buf)) return 1;
        printf("kernel timer trigger active: on=%dms off=%dms\n"
               "(stop with: %s none)\n", on_ms, off_ms, argv[0]);
        return 0;
    }

    if (!strcmp(cmd, "none")) {
        if (ensure_no_trigger()) return 1;
        return set_brightness(0) ? 1 : 0;
    }

    usage(argv[0]);
    return 2;
}
