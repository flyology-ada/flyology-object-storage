#include <stddef.h>

void flyology_object_storage_secure_erase(void *address, size_t bytes)
{
    volatile unsigned char *cursor = (volatile unsigned char *)address;

    while (bytes > 0U) {
        *cursor++ = 0U;
        --bytes;
    }
}
