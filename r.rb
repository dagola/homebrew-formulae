class R < Formula
  desc "Software environment for statistical computing"
  homepage "https://www.r-project.org/"
  url "https://cran.r-project.org/src/base/R-3/R-3.5.0.tar.gz"
  sha256 "fd1725535e21797d3d9fea8963d99be0ba4c3aecadcf081b43e261458b416870"
  revision 1

  bottle do
    sha256 "e65df345554df730d9a3d90554a4afe345f2023712cddfea2e146496a04c7236" => :high_sierra
    sha256 "cc9a616bd0981ead6f885015e1e41ae7c057e7c15c1e3d86d4fee7fc736130f2" => :sierra
    sha256 "c5e9ef1321dfc402102fac4e0343ba1b12131a9c1c21d03e5d316a720d343dba" => :el_capitan
  end

  depends_on "pkg-config" => :build
  depends_on "gcc" # for gfortran
  depends_on "gettext"
  depends_on "jpeg"
  depends_on "libpng"
  depends_on "pcre"
  depends_on "readline"
  depends_on "xz"
  depends_on "openblas" => :optional
  depends_on :java => :optional

  ## SRF - Add additional R capabilities (comment out if undesired)
  depends_on :x11 # SRF - X11 necessary for tcl-tk since tk.h includes X11 headers. See section A.2.1 Tcl/Tk at < https://cran.r-project.org/doc/manuals/r-release/R-admin.html >
  depends_on "texinfo" => :optional
  depends_on "libtiff" => :optional
  depends_on "cairo" => :optional # SRF - Cairo must be build with with X11 support. Use brew install sethrfore/r-srf/cairo
  depends_on "icu4c" => :optional
  depends_on "pango" => :optional

  # needed to preserve executable permissions on files without shebangs
  skip_clean "lib/R/bin"

  resource "gss" do
    url "https://cloud.r-project.org/src/contrib/gss_2.1-9.tar.gz", :using => :nounzip
    mirror "https://mirror.las.iastate.edu/CRAN/src/contrib/gss_2.1-9.tar.gz"
    sha256 "176cce8ddd939afb9ec3de6c731d13fbff38bc8f0291cf9c7aa4bf35491084bc"
  end

  def install
    # Fix dyld: lazy symbol binding failed: Symbol not found: _clock_gettime
    if MacOS.version == "10.11" && MacOS::Xcode.installed? &&
       MacOS::Xcode.version >= "8.0"
      ENV["ac_cv_have_decl_clock_gettime"] = "no"
    end

    ## SRF - Add cairo capability (comment/uncomment corresponding cairo args below as necessary)
    # Fix cairo detection with Quartz-only cairo
    # inreplace ["configure", "m4/cairo.m4"], "cairo-xlib.h", "cairo.h"

    args = [
      "--prefix=#{prefix}",
      "--enable-memory-profiling",
      "--with-x", # SRF - Add X11 support (comment --without-x). Necessary for tcl-tk support.
      "--with-aqua",
      "--with-lapack",
      "--enable-R-shlib",
      "SED=/usr/bin/sed", # don't remember Homebrew's sed shim
      "--with-tcltk", # SRF - Add tcl-tk support.
      "--with-tcl-config=/System/Library/Frameworks/Tcl.framework/tclConfig.sh", # SRF - Point to system tcl config file (requires Command Line tools to be installed).
      "--with-tk-config=/System/Library/Frameworks/Tk.framework/tkConfig.sh" # SRF - Point to system tk config file (requires Command Line tools to be installed).
    ]

    if build.with? "openblas"
      args << "--with-blas=-L#{Formula["openblas"].opt_lib} -lopenblas"
      ENV.append "LDFLAGS", "-L#{Formula["openblas"].opt_lib}"
    else
      args << "--with-blas=-framework Accelerate"
      ENV.append_to_cflags "-D__ACCELERATE__" if ENV.compiler != :clang
    end

    if build.with? "java"
      args << "--enable-java"
    else
      args << "--disable-java"
    end

    ## SRF - Add Cairo support
    if build.with? "cairo"
      args << "--with-cairo"
    else
      args << "--without-cairo"
    end

    # Help CRAN packages find gettext and readline
    ["gettext", "readline"].each do |f|
      ENV.append "CPPFLAGS", "-I#{Formula[f].opt_include}"
      ENV.append "LDFLAGS", "-L#{Formula[f].opt_lib}"
    end

    system "./configure", *args
    system "make"
    ENV.deparallelize do
      system "make", "install"
    end

    cd "src/nmath/standalone" do
      system "make"
      ENV.deparallelize do
        system "make", "install"
      end
    end

    r_home = lib/"R"

    # make Homebrew packages discoverable for R CMD INSTALL
    inreplace r_home/"etc/Makeconf" do |s|
      s.gsub!(/^CPPFLAGS =.*/, "\\0 -I#{HOMEBREW_PREFIX}/include")
      s.gsub!(/^LDFLAGS =.*/, "\\0 -L#{HOMEBREW_PREFIX}/lib")
      s.gsub!(/.LDFLAGS =.*/, "\\0 $(LDFLAGS)")
    end

    include.install_symlink Dir[r_home/"include/*"]
    lib.install_symlink Dir[r_home/"lib/*"]

    # avoid triggering mandatory rebuilds of r when gcc is upgraded
    inreplace lib/"R/etc/Makeconf", Formula["gcc"].prefix.realpath,
                                    Formula["gcc"].opt_prefix
  end

  def post_install
    short_version =
      `#{bin}/Rscript -e 'cat(as.character(getRversion()[1,1:2]))'`.strip
    site_library = HOMEBREW_PREFIX/"lib/R/#{short_version}/site-library"
    site_library.mkpath
    ln_s site_library, lib/"R/site-library"
  end

  test do
    assert_equal "[1] 2", shell_output("#{bin}/Rscript -e 'print(1+1)'").chomp
    assert_equal ".dylib", shell_output("#{bin}/R CMD config DYLIB_EXT").chomp

    testpath.install resource("gss")
    system bin/"R", "CMD", "INSTALL", "--library=.", Dir["gss*"].first
    assert_predicate testpath/"gss/libs/gss.so", :exist?,
                     "Failed to install gss package"
  end
end