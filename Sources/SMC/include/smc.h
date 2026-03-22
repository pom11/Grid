#ifndef SMC_H
#define SMC_H

#include <stdint.h>
#include <stdbool.h>
#include <IOKit/IOKitLib.h>

typedef struct {
    char key[5];
    uint32_t dataSize;
    char dataType[5];
    uint8_t bytes[32];
} SMCVal_t;

bool smc_open(void);
void smc_close(void);
bool smc_read_key(const char *key, SMCVal_t *val);
double smc_get_temperature(const char *key);

// Key enumeration — returns total number of SMC keys
uint32_t smc_get_key_count(void);
// Read key name at index (0-based). Returns false if index out of range.
bool smc_get_key_at_index(uint32_t index, char *key_out);

#endif
