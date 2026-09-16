<?php
// Fixtures for the PHP half of the pack Dendro ships.
//
// A line marked `dendro-expect: <rule>` must be reported by that rule and an unmarked line
// must not be, so the near-miss written beside each rule is as much of the test as the
// match is. This file is deliberately bad PHP and lives under `test/` for that reason:
// `src/` is what the dogfood gate scans.
//
// A comment is a named node in this grammar, so a marker trailing a `{` becomes the block's
// first child and a rule anchored on "the block holds nothing but this" stops matching.
// Every such rule is marked from the line above instead.

// --- banner_comment ---

// dendro-expect: banner_comment
// ========================================

// dendro-expect: banner_comment
// ----------------------------------------

// --- A rule with a title in it is a heading and stays ---

// --- boolean_return ---

function writes_the_test_out($c) {
    // dendro-expect: boolean_return
    if ($c) {
        return true;
    } else {
        return false;
    }
}

function returns_the_value($c, $x) {
    if ($c) {
        return true;
    } else {
        return $x;
    }
}

// --- unreachable_branch ---

function repeats_a_condition($x) {
    if ($x > 0) {  // dendro-expect: unreachable_branch
        return 1;
    } elseif ($x > 0) {
        return 2;
    }
    return 3;
}

function repeats_a_later_condition($x, $y) {
    if ($x > 0) {  // dendro-expect: unreachable_branch
        return 1;
    } elseif ($y > 0) {
        return 2;
    } elseif ($y > 0) {
        return 3;
    }
    return 4;
}

function tests_two_things($x, $y) {
    if ($x > 0) {
        return 1;
    } elseif ($y > 0) {
        return 2;
    }
    return 3;
}

// --- manual_min_max ---

function picks_the_larger($a, $b) {
    // dendro-expect: manual_min_max
    if ($a > $b) {
        return $a;
    } else {
        return $b;
    }
}

function picks_a_floor($a, $b) {
    if ($a > $b) {
        return $a;
    } else {
        return 0;
    }
}

// --- swallowed_error, try_density ---

function swallows($work) {
    try {  // dendro-expect: try_density
        return $work();
        // dendro-expect: swallowed_error
    } catch (Exception $e) {
        return null;
    }
}

function converts_a_failure($work) {
    try {  // dendro-expect: try_density
        return $work();
    } catch (JsonException $e) {
        return null;
    }
}

function handles_the_error($work, $log) {
    try {  // dendro-expect: try_density
        return $work();
    } catch (Exception $e) {
        $log($e);
        return null;
    }
}

// --- boolean_equality ---

function compares_a_flag($flag) {
    if ($flag == true) {  // dendro-expect: boolean_equality
        return 1;
    }
    if (false !== $flag) {  // dendro-expect: boolean_equality
        return 2;
    }
    if ($flag) {
        return 3;
    }
    return 0;
}

// --- empty_check ---

function counts_to_find_out($xs) {
    if (count($xs) == 0) {  // dendro-expect: empty_check
        return 1;
    }
    if (0 === count($xs)) {  // dendro-expect: empty_check
        return 2;
    }
    if (count($xs) == 1) {
        return 3;
    }
    if (empty($xs)) {
        return 4;
    }
    return 0;
}

// --- redundant_conversion ---

function converts_and_back($x, $s) {
    $a = intval(strval($x));  // dendro-expect: redundant_conversion
    $b = strval(intval($s));  // dendro-expect: redundant_conversion
    $c = intval($s);
    $d = strval($x);
    return [$a, $b, $c, $d];
}

// --- redundant_keys ---

function asks_a_key_view($d, $k) {
    if (in_array($k, array_keys($d))) {  // dendro-expect: redundant_keys
        return 1;
    }
    if (array_key_exists($k, $d)) {
        return 2;
    }
    return 0;
}

// --- type_check_density ---

function checks_every_argument($a, $b, $c) {
    // dendro-expect: type_check_density
    if (!($a instanceof Widget)) {
        throw new InvalidArgumentException("a");
    }
    // dendro-expect: type_check_density
    if (!($b instanceof Gadget)) {
        throw new InvalidArgumentException("b");
    }
    // dendro-expect: type_check_density
    if (!($c instanceof Doodad)) {
        throw new InvalidArgumentException("c");
    }
    return [$a, $b, $c];
}

function asks_once($a) {
    if ($a instanceof Widget) {
        return $a;
    }
    return 0;
}

// --- null_guard_density ---

function guards_every_argument($a, $b, $c) {
    // dendro-expect: null_guard_density
    if ($a === null) {
        return null;
    }
    // dendro-expect: null_guard_density
    if ($b === null) {
        return null;
    }
    // dendro-expect: null_guard_density
    if ($c === null) {
        return;
    }
    return [$a, $b, $c];
}

function substitutes_a_default($a, $fallback) {
    if ($a === null) {
        return $fallback;
    }
    return $a;
}

// --- empty_error_type ---

class BareError extends Exception {}  // dendro-expect: empty_error_type

class CarriesAPath extends Exception
{
    private $path;

    public function __construct($path)
    {
        parent::__construct($path);
        $this->path = $path;
    }
}

class NotAnError extends Base {}
