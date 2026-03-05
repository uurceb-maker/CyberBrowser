#ifndef XrayBridge_h
#define XrayBridge_h

// Placeholder header for future Go/C bridge integration.
// Real symbols should be exposed here when libxray is linked.

#ifdef __cplusplus
extern "C" {
#endif

int xray_start(const char *config_path);
void xray_stop(void);

#ifdef __cplusplus
}
#endif

#endif /* XrayBridge_h */
