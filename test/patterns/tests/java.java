// Fixtures for the Java half of the pack Dendro ships.
//
// A line marked `dendro-expect: <rule>` must be reported by that rule and an unmarked line
// must not be, so the near-miss written beside each rule is as much of the test as the
// match is. This file is deliberately bad Java and lives under `test/` for that reason:
// `src/` is what the dogfood gate scans.
//
// A comment is a named node in this grammar, so a marker trailing a `{` becomes the block's
// first child and a rule anchored on "the block holds nothing but this" stops matching.
// Every such rule is marked from the line above instead.

import java.util.List;
import java.util.Map;

// --- banner_comment ---

// dendro-expect: banner_comment
// ========================================

// dendro-expect: banner_comment
// ----------------------------------------

// --- A rule with a title in it is a heading and stays ---

class Fixtures {

    // --- boolean_return ---

    boolean writesTheTestOut(boolean c) {
        // dendro-expect: boolean_return
        if (c) {
            return true;
        } else {
            return false;
        }
    }

    boolean returnsTheValue(boolean c, boolean x) {
        if (c) {
            return true;
        } else {
            return x;
        }
    }

    // --- unreachable_branch ---

    int repeatsACondition(int x) {
        if (x > 0) {  // dendro-expect: unreachable_branch
            return 1;
        } else if (x > 0) {
            return 2;
        }
        return 3;
    }

    int testsTwoThings(int x, int y) {
        if (x > 0) {
            return 1;
        } else if (y > 0) {
            return 2;
        }
        return 3;
    }

    // --- manual_min_max ---

    int picksTheLarger(int a, int b) {
        // dendro-expect: manual_min_max
        if (a > b) {
            return a;
        } else {
            return b;
        }
    }

    int picksAFloor(int a, int b) {
        if (a > b) {
            return a;
        } else {
            return 0;
        }
    }

    // --- swallowed_error, try_density ---

    String swallows(Work work) {
        try {  // dendro-expect: try_density
            return work.run();
            // dendro-expect: swallowed_error
        } catch (Exception e) {
            return null;
        }
    }

    String convertsAFailure(Work work) {
        try {  // dendro-expect: try_density
            return work.run();
        } catch (NumberFormatException e) {
            return null;
        }
    }

    String closesWhatItOpened(Source source) {
        try (Reader r = source.open()) {  // dendro-expect: try_density
            return r.read();
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    String handlesTheError(Work work, Log log) {
        try {  // dendro-expect: try_density
            return work.run();
        } catch (Exception e) {
            log.warn(e);
            return null;
        }
    }

    // --- boolean_equality ---

    int comparesAFlag(boolean flag) {
        if (flag == true) {  // dendro-expect: boolean_equality
            return 1;
        }
        if (false != flag) {  // dendro-expect: boolean_equality
            return 2;
        }
        if (flag) {
            return 3;
        }
        return 0;
    }

    // --- empty_check ---

    int countsToFindOut(List<String> xs) {
        if (xs.size() == 0) {  // dendro-expect: empty_check
            return 1;
        }
        if (0 == xs.size()) {  // dendro-expect: empty_check
            return 2;
        }
        if (xs.size() == 1) {
            return 3;
        }
        if (xs.isEmpty()) {
            return 4;
        }
        return 0;
    }

    // --- redundant_conversion ---

    String convertsAndBack(int x, String s) {
        int a = Integer.parseInt(String.valueOf(x));  // dendro-expect: redundant_conversion
        String b = String.valueOf(Integer.parseInt(s));  // dendro-expect: redundant_conversion
        int c = Integer.parseInt(s);
        String d = String.valueOf(x);
        return b + d + a + c;
    }

    // --- redundant_keys ---

    int asksAKeyView(Map<String, String> m, String k) {
        if (m.keySet().contains(k)) {  // dendro-expect: redundant_keys
            return 1;
        }
        if (m.containsKey(k)) {
            return 2;
        }
        return 0;
    }

    // --- type_equality ---

    int asksForAnExactType(Object x) {
        if (x.getClass() == String.class) {  // dendro-expect: type_equality
            return 1;
        }
        if (String.class != x.getClass()) {  // dendro-expect: type_equality
            return 2;
        }
        if (x instanceof String) {
            return 3;
        }
        return 0;
    }

    // --- type_check_density ---

    void checksEveryArgument(Object a, Object b, Object c) {
        // dendro-expect: type_check_density
        if (!(a instanceof String)) {
            throw new IllegalArgumentException("a");
        }
        // dendro-expect: type_check_density
        if (!(b instanceof Integer)) {
            throw new IllegalArgumentException("b");
        }
        // dendro-expect: type_check_density
        if (!(c instanceof List)) {
            throw new IllegalArgumentException("c");
        }
    }

    Object asksOnce(Object a) {
        if (a instanceof String) {
            return a;
        }
        return null;
    }

    // --- null_guard_density ---

    String guardsEveryArgument(String a, String b, String c) {
        // dendro-expect: null_guard_density
        if (a == null) {
            return null;
        }
        if (b == null) return null;  // dendro-expect: null_guard_density
        // dendro-expect: null_guard_density
        if (c == null) {
            return null;
        }
        return a;
    }

    String substitutesADefault(String a, String fallback) {
        if (a == null) {
            return fallback;
        }
        return a;
    }
}

// --- empty_error_type ---

class BareError extends Exception {}  // dendro-expect: empty_error_type

class CarriesAPath extends Exception {
    private final String path;

    CarriesAPath(String path) {
        super(path);
        this.path = path;
    }
}

class NotAnError extends Base {}
