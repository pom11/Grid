#include "smc.h"
#include <IOKit/IOKitLib.h>
#include <string.h>

// SMC command selectors
#define SMC_CMD_READ_BYTES   5
#define SMC_CMD_READ_KEYINFO 9
#define SMC_CMD_READ_INDEX   8

// Correct SMC kernel struct — must be exactly 80 bytes
typedef struct {
    uint32_t key;
    struct { uint8_t major, minor, build, reserved; uint16_t release; } vers;
    struct { uint16_t version, length; uint32_t cpuPLimit, gpuPLimit, memPLimit; } pLimitData;
    struct { uint32_t dataSize; uint32_t dataType; uint8_t dataAttributes; } keyInfo;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint32_t data32;
    uint8_t bytes[32];
} SMCKeyData_t;

static io_connect_t conn = 0;

static uint32_t str_to_uint32(const char *str) {
    uint32_t total = 0;
    for (int i = 0; i < 4 && str[i]; i++) {
        total = (total << 8) | (uint8_t)str[i];
    }
    return total;
}

static kern_return_t smc_call(SMCKeyData_t *input, SMCKeyData_t *output) {
    size_t outSize = sizeof(SMCKeyData_t);
    return IOConnectCallStructMethod(conn, 2, input, sizeof(SMCKeyData_t), output, &outSize);
}

bool smc_open(void) {
    io_service_t service = IOServiceGetMatchingService(
        0, IOServiceMatching("AppleSMC")
    );
    if (!service) return false;
    kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, &conn);
    IOObjectRelease(service);
    return result == KERN_SUCCESS;
}

void smc_close(void) {
    if (conn) {
        IOServiceClose(conn);
        conn = 0;
    }
}

bool smc_read_key(const char *key, SMCVal_t *val) {
    SMCKeyData_t input = {0};
    SMCKeyData_t output = {0};

    input.key = str_to_uint32(key);
    input.data8 = SMC_CMD_READ_KEYINFO;
    if (smc_call(&input, &output) != KERN_SUCCESS) return false;

    val->dataSize = output.keyInfo.dataSize;
    uint32_t dt = output.keyInfo.dataType;
    val->dataType[0] = (dt >> 24) & 0xFF;
    val->dataType[1] = (dt >> 16) & 0xFF;
    val->dataType[2] = (dt >> 8) & 0xFF;
    val->dataType[3] = dt & 0xFF;
    val->dataType[4] = 0;

    input.keyInfo.dataSize = output.keyInfo.dataSize;
    input.data8 = SMC_CMD_READ_BYTES;
    memset(&output, 0, sizeof(output));
    if (smc_call(&input, &output) != KERN_SUCCESS) return false;

    memcpy(val->bytes, output.bytes, sizeof(val->bytes));
    strncpy(val->key, key, 4);
    val->key[4] = 0;
    return true;
}

uint32_t smc_get_key_count(void) {
    SMCKeyData_t input = {0}, output = {0};
    input.key = str_to_uint32("#KEY");
    input.data8 = SMC_CMD_READ_KEYINFO;
    if (smc_call(&input, &output) != KERN_SUCCESS) return 0;

    input.keyInfo.dataSize = output.keyInfo.dataSize;
    input.data8 = SMC_CMD_READ_BYTES;
    memset(&output, 0, sizeof(output));
    if (smc_call(&input, &output) != KERN_SUCCESS) return 0;

    return ((uint32_t)output.bytes[0] << 24) | ((uint32_t)output.bytes[1] << 16) |
           ((uint32_t)output.bytes[2] << 8) | output.bytes[3];
}

bool smc_get_key_at_index(uint32_t index, char *key_out) {
    SMCKeyData_t input = {0}, output = {0};
    input.data8 = SMC_CMD_READ_INDEX;
    input.data32 = index;
    if (smc_call(&input, &output) != KERN_SUCCESS) return false;

    key_out[0] = (output.key >> 24) & 0xFF;
    key_out[1] = (output.key >> 16) & 0xFF;
    key_out[2] = (output.key >> 8) & 0xFF;
    key_out[3] = output.key & 0xFF;
    key_out[4] = 0;
    return true;
}

double smc_get_temperature(const char *key) {
    SMCVal_t val = {0};
    if (!smc_read_key(key, &val)) return -1.0;

    // All zero bytes means no valid reading
    bool allZero = true;
    for (uint32_t i = 0; i < val.dataSize && i < 32; i++) {
        if (val.bytes[i] != 0) { allZero = false; break; }
    }
    if (allZero) return -1.0;

    uint16_t raw16 = ((uint16_t)val.bytes[0] << 8) | val.bytes[1];

    // Signed fixed-point formats (spXY)
    if (val.dataSize == 2) {
        if (memcmp(val.dataType, "sp78", 4) == 0) return (int16_t)raw16 / 256.0;
        if (memcmp(val.dataType, "sp87", 4) == 0) return (int16_t)raw16 / 128.0;
        if (memcmp(val.dataType, "sp96", 4) == 0) return (int16_t)raw16 / 64.0;
        if (memcmp(val.dataType, "sp69", 4) == 0) return (int16_t)raw16 / 512.0;
        if (memcmp(val.dataType, "sp5a", 4) == 0) return (int16_t)raw16 / 1024.0;
        if (memcmp(val.dataType, "sp4b", 4) == 0) return (int16_t)raw16 / 2048.0;
        if (memcmp(val.dataType, "sp3c", 4) == 0) return (int16_t)raw16 / 4096.0;
        if (memcmp(val.dataType, "sp1e", 4) == 0) return raw16 / 16384.0;
        if (memcmp(val.dataType, "spb4", 4) == 0) return (int16_t)raw16 / 16.0;
        if (memcmp(val.dataType, "spf0", 4) == 0) return (int16_t)raw16;
        // Unsigned fixed-point
        if (memcmp(val.dataType, "fpe2", 4) == 0) return raw16 / 4.0;
        if (memcmp(val.dataType, "fp2e", 4) == 0) return raw16 / 16384.0;
        // Unsigned integers
        if (memcmp(val.dataType, "ui16", 4) == 0) return (double)raw16;
    }

    // IEEE 754 single-precision float (4 bytes)
    if (val.dataSize == 4 && memcmp(val.dataType, "flt ", 4) == 0) {
        float f;
        memcpy(&f, val.bytes, 4);
        return (double)f;
    }

    // Unsigned 8-bit integer
    if (val.dataSize == 1 && memcmp(val.dataType, "ui8 ", 4) == 0) {
        return (double)val.bytes[0];
    }

    return -1.0;
}
