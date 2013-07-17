# WARNING: automatically generated file
# Generated by 'gem nix' command that comes from 'nix' gem
g: # Get dependencies from patched gems
{
  aliases = {
    sequel = g.sequel_4_0_0;
    sqlite3 = g.sqlite3_1_3_7;
  };
  gem_nix_args = [ ''sequel'' ''sqlite3'' ];
  gems = {
    sequel_4_0_0 = {
      basename = ''sequel'';
      meta = {
        description = ''The Database Toolkit for Ruby'';
        homepage = ''http://sequel.rubyforge.org'';
        longDescription = ''The Database Toolkit for Ruby'';
      };
      name = ''sequel-4.0.0'';
      requiredGems = [  ];
      sha256 = ''17kqm0vd15p9qxbgcysvmg6a046fd7zvxl3xzpsh00pg6v454svm'';
    };
    sqlite3_1_3_7 = {
      basename = ''sqlite3'';
      meta = {
        description = ''This module allows Ruby programs to interface with the SQLite3 database engine (http://www.sqlite.org)'';
        homepage = ''http://github.com/luislavena/sqlite3-ruby'';
        longDescription = ''This module allows Ruby programs to interface with the SQLite3
database engine (http://www.sqlite.org).  You must have the
SQLite engine installed in order to build this module.

Note that this module is only compatible with SQLite 3.6.16 or newer.'';
      };
      name = ''sqlite3-1.3.7'';
      requiredGems = [  ];
      sha256 = ''0qlr9f4l57cbcf66gdswip9qcx8l21yhh0fsrqz9k7mad7jia4by'';
    };
  };
}