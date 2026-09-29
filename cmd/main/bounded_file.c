#include <errno.h>
#include <stdio.h>
#include <string.h>

#ifdef _WIN32
#include <wchar.h>
#endif

#include "moonbit.h"

#ifdef _WIN32
typedef moonbit_string_t binschema_input_path_t;
#else
typedef moonbit_bytes_t binschema_input_path_t;
#endif

MOONBIT_FFI_EXPORT FILE *
binschema_input_file_open(binschema_input_path_t path) {
#ifdef _WIN32
  return _wfopen((const wchar_t *)path, L"rb");
#else
  return fopen((const char *)path, "rb");
#endif
}

MOONBIT_FFI_EXPORT int binschema_input_file_is_null(FILE *file) {
  return file == NULL;
}

MOONBIT_FFI_EXPORT int binschema_input_file_read(FILE *file,
                                                 moonbit_bytes_t buffer,
                                                 int count) {
  size_t bytes_read = fread(buffer, 1, (size_t)count, file);
  if (bytes_read == 0 && ferror(file)) {
    return -1;
  }
  return (int)bytes_read;
}

MOONBIT_FFI_EXPORT int binschema_input_file_close(FILE *file) {
  return fclose(file);
}

MOONBIT_FFI_EXPORT moonbit_bytes_t binschema_input_file_error_message(void) {
  const char *message = strerror(errno);
  size_t length = strlen(message);
  moonbit_bytes_t bytes = moonbit_make_bytes(length, 0);
  memcpy(bytes, message, length);
  return bytes;
}
