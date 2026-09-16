@testitem ":divisible_class splits a class whose methods share no state" setup = [Fixtures] tags = [:class_cohesion] begin
    # `read_a`/`write_a` touch `self.a`, `read_b`/`write_b` touch `self.b`, and nothing
    # joins the two pairs. The constructor assigns both fields, so counting it would make
    # every class one component; it is dropped from the method set.
    src = """
    class Store:
        def __init__(self):
            self.a = 1
            self.b = 2

        def read_a(self):
            return self.a

        def write_a(self, v):
            self.a = v

        def read_b(self):
            return self.b

        def write_b(self, v):
            self.b = v
    """
    files = [Fixtures.parsedfile(:python, src; file = "f.py")]
    f = only(Dendro.cluster_divisible_class(files; band = (2, 3), min_methods = 4))

    @test f.metric == :divisible_class
    @test f.kind == :scalar
    @test f.value == 2
    @test f.absolute == :warn
    # One class, so the percentile stays off and the absolute band alone fires.
    @test f.percentile === nothing
    @test [(l.unit, l.line) for l in f.locations] == [("Store", 1), ("read_a", 6), ("read_b", 12)]
end

@testitem ":divisible_class joins two groups a method call links" setup = [Fixtures] tags = [:class_cohesion] begin
    # `read_b` calls `read_a`, so the two field groups are one concern after all. A class
    # of one component names nothing to split and never reports.
    src = """
    class Store:
        def __init__(self):
            self.a = 1
            self.b = 2

        def read_a(self):
            return self.a

        def write_a(self, v):
            self.a = v

        def read_b(self):
            return self.b + self.read_a()

        def write_b(self, v):
            self.b = v
    """
    files = [Fixtures.parsedfile(:python, src; file = "f.py")]
    @test isempty(Dendro.cluster_divisible_class(files; band = (2, 3), min_methods = 4))
end

@testitem ":divisible_class joins two groups an ordinary method touching both" setup = [Fixtures] tags = [:class_cohesion] begin
    # The constructor is the one method the rule drops. A plain method reading both fields
    # is evidence the two groups belong together, and it links them.
    src = """
    class Store:
        def __init__(self):
            self.a = 1
            self.b = 2

        def read_a(self):
            return self.a

        def write_a(self, v):
            self.a = v

        def read_b(self):
            return self.b

        def both(self):
            return self.a + self.b
    """
    files = [Fixtures.parsedfile(:python, src; file = "f.py")]
    @test isempty(Dendro.cluster_divisible_class(files; band = (2, 3), min_methods = 4))
end

@testitem ":divisible_class gives a nested class its own methods" setup = [Fixtures] tags = [:class_cohesion] begin
    # `Inner`'s methods belong to `Inner`, not to `Outer`. `Outer` keeps two methods of its
    # own, below the floor, so only the nested class is scored.
    src = """
    class Outer:
        def one(self):
            return self.x

        def two(self):
            return self.y

        class Inner:
            def read_a(self):
                return self.a

            def write_a(self, v):
                self.a = v

            def read_b(self):
                return self.b

            def write_b(self, v):
                self.b = v
    """
    files = [Fixtures.parsedfile(:python, src; file = "f.py")]
    f = only(Dendro.cluster_divisible_class(files; band = (2, 3), min_methods = 4))
    @test f.value == 2
    @test first(f.locations).unit == "Inner"
end

@testitem ":divisible_class leaves a class below the method floor unscored" setup = [Fixtures] tags = [:class_cohesion] begin
    # Two methods sharing nothing is a pair, not a class wanting a split.
    src = """
    class Store:
        def read_a(self):
            return self.a

        def read_b(self):
            return self.b
    """
    files = [Fixtures.parsedfile(:python, src; file = "f.py")]
    @test isempty(Dendro.cluster_divisible_class(files; band = (2, 3), min_methods = 4))
end

@testitem ":divisible_class keeps a cohesive class in the percentile population" setup = [Fixtures] tags = [:class_cohesion] begin
    # Five cohesive classes, one of two components and one of three. The band is set out of
    # reach, so only the corpus rank can fire, and it fires on the three-component class
    # alone: the cohesive classes are the population the other two are ranked against.
    # One field group per letter: two methods reading and writing it, joined to nothing
    # else, so the component count is the letter count.
    pair(g, i) = "    def read_$g$i(self):\n        return self.$g\n    def write_$g$i(self, v):\n        self.$g = v\n"
    klass(name, fields) = string("class $name:\n", join(pair(g, i) for (i, g) in enumerate(fields)), "\n")
    src = join(
        [
            [klass("C$i", ["a", "a"]) for i in 1:5]
            klass("Two", ["a", "b"])
            klass("Three", ["a", "b", "c"])
        ]
    )
    files = [Fixtures.parsedfile(:python, src; file = "f.py")]
    findings = Dendro.cluster_divisible_class(files; band = (99, 100), cut = 0.95, min_methods = 4)
    f = only(findings)
    @test f.value == 3
    @test first(f.locations).unit == "Three"
    @test f.percentile == 1.0
end

@testitem ":divisible_class respects dendro-ignore on the class line" setup = [Fixtures] tags = [:class_cohesion] begin
    src = """
    # dendro-ignore: divisible_class
    class Store:
        def read_a(self):
            return self.a

        def write_a(self, v):
            self.a = v

        def read_b(self):
            return self.b

        def write_b(self, v):
            self.b = v
    """
    index = Fixtures.idx(:python, src)
    files = [
        Fixtures.parsedfile(
            :python, src; file = "f.py", directives = Dendro.suppressions(index; file = "f.py")
        ),
    ]
    f = only(Dendro.cluster_divisible_class(files; band = (2, 3), min_methods = 4))
    @test f.suppressed
end

@testitem ":divisible_class reads a class in every language whose methods live in one" setup = [Fixtures] tags = [:class_cohesion] begin
    # One fixture per covered language: a constructor assigning both fields, then two
    # methods on each field and nothing joining the pairs. Each is hand-written to the
    # language's own way of naming instance state, which is the whole of what the
    # `@field` capture has to get right.
    cases = [
        (
            lang = :java, name = "Store",
            src = """
            class Store {
              private int a;
              private int b;

              Store() { a = 0; b = 0; }

              int readA() { return a; }
              void writeA(int v) { a = v; }
              int readB() { return b; }
              int writeB(int v) { int a = v + 1; return b + a; }
            }
            """,
        ),
        (
            lang = :javascript, name = "Store",
            src = """
            class Store {
              constructor() { this.a = 0; this.b = 0; }
              readA() { return this.a; }
              writeA(v) { this.a = v; }
              readB() { return this.b; }
              writeB(v) { this.b = v; }
            }
            """,
        ),
        (
            lang = :typescript, name = "Store",
            src = """
            class Store {
              a: number = 0;
              b: number = 0;
              constructor() { this.a = 0; this.b = 0; }
              readA(): number { return this.a; }
              writeA(v: number) { this.a = v; }
              readB(): number { return this.b; }
              writeB(v: number) { this.b = v; }
            }
            """,
        ),
        (
            lang = :php, name = "Store",
            src = """
            <?php
            class Store {
              private \$a;
              private \$b;
              function __construct() { \$this->a = 0; \$this->b = 0; }
              function readA() { return \$this->a; }
              function writeA(\$v) { \$this->a = \$v; }
              function readB() { return \$this->b; }
              function writeB(\$v) { \$this->b = \$v; }
            }
            """,
        ),
        (
            lang = :ruby, name = "Store",
            src = """
            class Store
              def initialize
                @a = 0
                @b = 0
              end

              def read_a
                @a
              end

              def write_a(v)
                @a = v
              end

              def read_b
                @b
              end

              def write_b(v)
                @b = v
              end
            end
            """,
        ),
        (
            lang = :rust, name = "Store",
            src = """
            struct Store { a: i32, b: i32 }

            impl Store {
                fn read_a(&self) -> i32 { self.a }
                fn write_a(&mut self, v: i32) {
                    fn bump(x: i32) -> i32 { x + 1 }
                    self.a = bump(v);
                }
                fn read_b(&self) -> i32 { self.b }
                fn write_b(&mut self, v: i32) { self.b = v; }
            }
            """,
        ),
    ]
    @testset "$(case.lang)" for case in cases
        files = [Fixtures.parsedfile(case.lang, case.src)]
        f = only(Dendro.cluster_divisible_class(files; band = (2, 3), min_methods = 4))
        @test f.value == 2
        @test first(f.locations).unit == case.name
        # The nested `bump` does the method's work rather than being a method of its own,
        # so the four methods are all the class has.
        @test length(f.locations) == 3
    end
end

@testitem ":divisible_class names a Rust trait impl by the type it implements" setup = [Fixtures] tags = [:class_cohesion] begin
    # `impl Display for Store` is a class whose methods belong to `Store`. The lexical
    # first name is the trait, which would label every trait impl in a file the same way.
    src = """
    impl Display for Store {
        fn read_a(&self) -> i32 { self.a }
        fn write_a(&mut self, v: i32) { self.a = v; }
        fn read_b(&self) -> i32 { self.b }
        fn write_b(&mut self, v: i32) { self.b = v; }
    }
    """
    files = [Fixtures.parsedfile(:rust, src)]
    f = only(Dendro.cluster_divisible_class(files; band = (2, 3), min_methods = 4))
    @test first(f.locations).unit == "Store"
end

@testitem ":divisible_class says nothing about Julia, whose methods are not in the type" setup = [Fixtures] tags = [:class_cohesion] begin
    # A Julia struct's methods are whatever dispatches on it anywhere in the program, so
    # gathering them would need dispatch resolution. The query tags no `@class` and the
    # pass reads nothing rather than guessing from a file's layout.
    src = """
    struct Store
        a::Int
        b::Int
    end

    read_a(s::Store) = s.a
    write_a(s::Store, v) = Store(v, s.b)
    read_b(s::Store) = s.b
    write_b(s::Store, v) = Store(s.a, v)
    """
    files = [Fixtures.parsedfile(:julia, src; file = "f.jl")]
    @test isempty(Dendro.cluster_divisible_class(files; band = (2, 3), min_methods = 2))
end

@testitem ":divisible_class reads its band and its toggle from the config" tags = [:class_cohesion] begin
    using Dendro: analyze, discover_config

    mktempdir() do dir
        # Four methods on two fields, so the class scores two. The rule is off unless the
        # config turns it on, and the default band is out of reach at that size, so a
        # project that wants the reading sets both in its own `.dendro.toml`.
        write(
            joinpath(dir, "s.py"),
            """
            class Store:
                def read_a(self):
                    return self.a

                def write_a(self, v):
                    self.a = v

                def read_b(self):
                    return self.b

                def write_b(self, v):
                    self.b = v
            """
        )

        plain = discover_config([dir]; use_files = false)
        @test isempty(filter(f -> f.metric === :divisible_class, analyze(dir; config = plain, cut = 2.0)))

        write(
            joinpath(dir, ".dendro.toml"),
            "[rules]\ndivisible_class = true\n\n[bands]\ndivisible_class = [2, 4]\n"
        )
        tuned = mktempdir() do xdg
            withenv("XDG_CONFIG_HOME" => xdg) do
                discover_config([dir])
            end
        end
        hits = filter(f -> f.metric === :divisible_class, analyze(dir; config = tuned, cut = 2.0))
        @test only(hits).value == 2

        write(joinpath(dir, ".dendro.toml"), "[bands]\ndivisible_class = [2, 4]\n")
        off = mktempdir() do xdg
            withenv("XDG_CONFIG_HOME" => xdg) do
                discover_config([dir])
            end
        end
        @test isempty(filter(f -> f.metric === :divisible_class, analyze(dir; config = off, cut = 2.0)))
    end
end

@testitem ":divisible_class reads a Java field a getter of the same name shadows" setup = [Fixtures] tags = [:class_cohesion] begin
    # Java lets a field and its accessor share a name, and the scope resolver hoists the
    # method, so `return hits` binds to the method `hits` rather than staying unresolved.
    # Only a local or an assignment shadows a field; a hoisted definition does not.
    src = """
    class Stats {
      private final long hits;
      private final long misses;
      private final String name;
      private final String owner;

      long hits() { return hits; }
      long total() { return hits + misses; }
      String name() { return name; }
      String label() { return name + owner; }
    }
    """
    files = [Fixtures.parsedfile(:java, src)]
    f = only(Dendro.cluster_divisible_class(files; band = (2, 3), min_methods = 4))
    @test f.value == 2
end

@testitem ":divisible_class reads a Rust tuple struct's numbered fields" setup = [Fixtures] tags = [:class_cohesion] begin
    # `self.0` names a field as much as `self.name` does. Rust spells a tuple struct's
    # fields with integers, so a capture reading only identifiers would see no state at
    # all and score every such impl by its method count.
    src = """
    struct Pair(i32, i32);

    impl Pair {
        fn first(&self) -> i32 { self.0 }
        fn twice_first(&self) -> i32 { self.0 * 2 }
        fn second(&self) -> i32 { self.1 }
        fn twice_second(&self) -> i32 { self.1 * 2 }
    }
    """
    files = [Fixtures.parsedfile(:rust, src)]
    f = only(Dendro.cluster_divisible_class(files; band = (2, 3), min_methods = 4))
    @test f.value == 2
end

@testitem ":divisible_class gives a Java enum and record their own methods" setup = [Fixtures] tags = [:class_cohesion] begin
    # An enum constant and a record component are instance state, and the methods reading
    # them live inside the declaration. Reading only `class` would hand those methods to
    # whatever class encloses them, which for a utility class holding a private enum is
    # every method of the enum.
    src = """
    final class Holder {
      private Holder() {}

      enum Mode {
        FAST, SLOW;

        private final String label = "m";
        private final String note = "n";

        String label() { return label; }
        String shout() { return label + "!"; }
        String note() { return note; }
        String quiet() { return note + "."; }
      }
    }
    """
    files = [Fixtures.parsedfile(:java, src)]
    f = only(Dendro.cluster_divisible_class(files; band = (2, 3), min_methods = 4))
    @test f.value == 2
    @test first(f.locations).unit == "Mode"
end
