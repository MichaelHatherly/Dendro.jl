@testitem ":member_count counts every member a class declares, constructors included" setup = [Fixtures] tags = [:class_size] begin
    # Six definitions inside the class, `__init__` among them. `:divisible_class` drops a
    # constructor because it links every field group to every other; a size reading counts
    # it, since a class with fifteen constructors is what the count is for.
    src = """
    class Store:
        def __init__(self):
            self.a = 1

        def read_a(self):
            return self.a

        def write_a(self, v):
            self.a = v

        def read_b(self):
            return self.b

        def write_b(self, v):
            self.b = v

        def flush(self):
            return None
    """
    files = [Fixtures.parsedfile(:python, src; file = "f.py")]
    f = only(Fixtures.member_counts(files; band = (5, 9)))

    @test f.metric == :member_count
    @test f.kind == :scalar
    @test f.value == 6
    @test f.absolute == :warn
    # One class, so the percentile stays off and the absolute band alone fires.
    @test f.percentile === nothing
    # One location at the declaration, not one per member: the edit the finding names is
    # the class, and a member list would report the same class six times.
    @test [(l.unit, l.line) for l in f.locations] == [("Store", 1)]
end

@testitem ":member_count gives a nested class its own members" setup = [Fixtures] tags = [:class_size] begin
    # `Inner`'s methods belong to `Inner`, so `Outer` counts one member and not three. A
    # closure written inside a method is that method's business and counts for neither.
    src = """
    class Outer:
        def a(self):
            def helper():
                return 0

            return helper()

        class Inner:
            def b(self):
                return 2

            def c(self):
                return 3
    """
    files = [Fixtures.parsedfile(:python, src; file = "f.py")]
    f = only(Fixtures.member_counts(files; band = (2, 3)))

    @test f.value == 2
    @test first(f.locations).unit == "Inner"
end

@testitem ":member_count reads the corpus rank once enough classes are scored" setup = [Fixtures] tags = [:class_size] begin
    # Six one-member classes and one of four, with the band out of reach, so only the
    # corpus rank can fire. Under the floor there is no rank to read and nothing reports.
    klass(name, n) = string("class $name:\n", join("    def m$i(self):\n        return $i\n" for i in 1:n), "\n")
    src = join([[klass("C$i", 1) for i in 1:6]; klass("Big", 4)])
    files = [Fixtures.parsedfile(:python, src; file = "f.py")]

    f = only(Fixtures.member_counts(files; band = (99, 100), cut = 0.95, min_classes = 5))
    @test f.value == 4
    @test first(f.locations).unit == "Big"
    @test f.percentile == 1.0

    @test isempty(Fixtures.member_counts(files; band = (99, 100), cut = 0.95, min_classes = 8))
end

@testitem ":member_count reads a class in every language whose methods live in one" setup = [Fixtures] tags = [:class_size] begin
    # One fixture per covered language, each a constructor and three methods, so the count
    # is four wherever the language names a constructor. Rust has none to name: an
    # associated `new` is an ordinary function, so its `impl` holds four plain methods.
    cases = [
        (
            lang = :python, name = "Store", members = 4, line = 1,
            src = """
            class Store:
                def __init__(self):
                    self.a = 0

                def read(self):
                    return self.a

                def write(self, v):
                    self.a = v

                def flush(self):
                    return None
            """,
        ),
        (
            lang = :java, name = "Store", members = 4, line = 1,
            src = """
            class Store {
              private int a;

              Store() { a = 0; }

              int read() { return a; }
              void write(int v) { a = v; }
              int twice() { return a + a; }
            }
            """,
        ),
        (
            lang = :javascript, name = "Store", members = 4, line = 1,
            src = """
            class Store {
              constructor() { this.a = 0; }
              read() { return this.a; }
              write(v) { this.a = v; }
              twice() { return this.a + this.a; }
            }
            """,
        ),
        (
            lang = :typescript, name = "Store", members = 4, line = 1,
            src = """
            class Store {
              a: number = 0;
              constructor() { this.a = 0; }
              read(): number { return this.a; }
              write(v: number) { this.a = v; }
              twice(): number { return this.a + this.a; }
            }
            """,
        ),
        (
            lang = :php, name = "Store", members = 4, line = 2,
            src = """
            <?php
            class Store {
              private \$a;
              function __construct() { \$this->a = 0; }
              function read() { return \$this->a; }
              function write(\$v) { \$this->a = \$v; }
              function twice() { return \$this->a + \$this->a; }
            }
            """,
        ),
        (
            lang = :ruby, name = "Store", members = 4, line = 1,
            src = """
            class Store
              def initialize
                @a = 0
              end

              def read
                @a
              end

              def write(v)
                @a = v
              end

              def twice
                @a + @a
              end
            end
            """,
        ),
        (
            lang = :rust, name = "Store", members = 4, line = 3,
            src = """
            struct Store { a: i32 }

            impl Store {
                fn new() -> Store { Store { a: 0 } }
                fn read(&self) -> i32 { self.a }
                fn write(&mut self, v: i32) { self.a = v; }
                fn twice(&self) -> i32 { self.a + self.a }
            }
            """,
        ),
    ]
    @testset "$(case.lang)" for case in cases
        files = [Fixtures.parsedfile(case.lang, case.src)]
        f = only(Fixtures.member_counts(files; band = (3, 9)))
        @test f.value == case.members
        @test [(l.unit, l.line) for l in f.locations] == [(case.name, case.line)]
    end
end

@testitem ":member_count says nothing where a type's methods sit outside it" setup = [Fixtures] tags = [:class_size] begin
    # The query tags no `@class` in these four, so there is no container to count members
    # of, and each language has its own reason for that.
    cases = [
        (
            lang = :julia,
            why = "a struct's methods are whatever dispatches on it anywhere",
            src = """
            struct Store
                a::Int
            end

            read_a(s::Store) = s.a
            write_a(s::Store, v) = Store(v)
            twice(s::Store) = s.a + s.a
            """,
        ),
        (
            lang = :go,
            why = "a receiver method is a file-scope sibling of the type",
            src = """
            package store

            type Store struct{ a int }

            func (s *Store) Read() int { return s.a }
            func (s *Store) Write(v int) { s.a = v }
            func (s *Store) Twice() int { return s.a + s.a }
            """,
        ),
        (
            lang = :c,
            why = "a struct holds data and the functions acting on it are file scope",
            src = """
            struct Store { int a; };

            int store_read(struct Store *s) { return s->a; }
            void store_write(struct Store *s, int v) { s->a = v; }
            int store_twice(struct Store *s) { return s->a + s->a; }
            """,
        ),
        (
            lang = :cpp,
            why = "a class declares its methods and defines them out of line",
            src = """
            class Store {
              int a;
            public:
              int read();
              void write(int v);
              int twice();
            };

            int Store::read() { return a; }
            void Store::write(int v) { a = v; }
            int Store::twice() { return a + a; }
            """,
        ),
    ]
    @testset "$(case.lang): $(case.why)" for case in cases
        files = [Fixtures.parsedfile(case.lang, case.src)]
        @test isempty(Fixtures.member_counts(files; band = (2, 3)))
    end
end

@testitem ":member_count respects dendro-ignore on the class line" setup = [Fixtures] tags = [:class_size] begin
    src = """
    # dendro-ignore: member_count
    class Store:
        def read_a(self):
            return self.a

        def write_a(self, v):
            self.a = v

        def read_b(self):
            return self.b
    """
    index = Fixtures.idx(:python, src)
    files = [
        Fixtures.parsedfile(
            :python, src; file = "f.py", directives = Dendro.suppressions(index; file = "f.py")
        ),
    ]
    f = only(Fixtures.member_counts(files; band = (2, 3)))
    @test f.value == 3
    @test f.suppressed
end

@testitem ":member_count reads its band from the config and runs by default" tags = [:class_size] begin
    using Dendro: analyze, discover_config

    mktempdir() do dir
        # Three members, under the default band, so the rule runs and says nothing until
        # the project retunes it. No `[rules]` key is needed: the count ships on.
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
            """
        )

        plain = discover_config([dir]; use_files = false)
        @test isempty(filter(f -> f.metric === :member_count, analyze(dir; config = plain, cut = 2.0)))

        write(joinpath(dir, ".dendro.toml"), "[bands]\nmember_count = [2, 4]\n")
        tuned = mktempdir() do xdg
            withenv("XDG_CONFIG_HOME" => xdg) do
                discover_config([dir])
            end
        end
        hits = filter(f -> f.metric === :member_count, analyze(dir; config = tuned, cut = 2.0))
        @test only(hits).value == 3
    end
end
