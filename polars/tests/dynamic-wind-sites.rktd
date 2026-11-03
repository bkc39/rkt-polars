(("tests/gc-pressure.rkt" call-with-collections "kills the thread that requests collections")
 ("tests/test-helpers.rkt" call-with-default-polars-format "restores the POLARS_FMT_ variables")
 ("tests/test-helpers.rkt" call-with-environment-variable "restores an environment variable"))
