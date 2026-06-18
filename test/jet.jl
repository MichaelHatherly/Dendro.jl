import JET

# JET's basic static analysis over Dendro's own modules. A type-level regression,
# a call that admits a no-method branch, fails the suite here rather than at runtime.
JET.test_package(Dendro; target_defined_modules = true, mode = :basic)
