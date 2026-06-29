; C linkage. A quoted `#include "foo.h"` splices a header's declarations into the
; including file, resolved relative to its directory. Angle-bracket system headers are
; outside the corpus and ignored. Node types match tree-sitter-cpp.

(preproc_include path: (string_literal) @include.path)
