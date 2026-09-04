<?php
// Reports what the base image actually provides at runtime. Keep the output on
// one line and prefixed with SMOKE-OK so the harness can assert on it.
$required = ['redis', 'imagick', 'mysqli', 'gd', 'intl', 'sodium', 'zip', 'mbstring'];
$missing = array_values(array_filter($required, fn($e) => !extension_loaded($e)));

printf(
    "SMOKE-OK php=%s missing=%s max_exec=%s memory=%s",
    PHP_VERSION,
    $missing ? implode(',', $missing) : 'none',
    ini_get('max_execution_time'),
    ini_get('memory_limit')
);
