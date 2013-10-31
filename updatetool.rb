#!/usr/bin/env ruby

require 'optparse'
require 'mechanize'
require 'logger'
require 'csv'
require 'distro-package.rb'
require 'package-updater.rb'
require 'security-advisory'
require 'sequel'
require 'set'

include PackageUpdater

log = Logger.new(STDOUT)
log.level = Logger::WARN
log.formatter = proc { |severity, datetime, progname, msg|
  "#{severity}: #{msg}\n"
}
PackageUpdater::Log = log

csv_report_file = nil
action = nil
pkgs_to_check = []
do_cve_update = false

db_path = './db.sqlite'
DB = Sequel.sqlite(db_path)
DistroPackage::DB = DB

distros_to_update = []

OptionParser.new do |o|
  o.on("-v", "Verbose output. Can be specified multiple times") do
    log.level -= 1
  end

  o.on("--list-arch", "List Arch packages") do
    distros_to_update << DistroPackage::Arch
  end

  o.on("--list-aur", "List AUR packages") do
    distros_to_update << DistroPackage::AUR
  end

  o.on("--list-nix", "List nixpkgs packages") do
    distros_to_update << DistroPackage::Nix
  end

  o.on("--list-deb", "List Debian packages") do
    distros_to_update << DistroPackage::Debian
  end

  o.on("--list-gentoo", "List Gentoo packages") do
    distros_to_update << DistroPackage::Gentoo
  end

  o.on("--output-csv FILE", "Write report in CSV format to FILE") do |f|
    csv_report_file = f
  end

  o.on("--check-pkg-version-match", "List Nix packages for which either tarball can't be parsed or its version doesn't match the package version") do
    action = :check_pkg_version_match
  end

  o.on("--check-updates", "list NixPkgs packages which have updates available") do
    action = :check_updates
    pkgs_to_check += DistroPackage::Nix.packages
  end

  o.on("--check-package PACKAGE", "Check what updates are available for PACKAGE") do |pkgname|
    action = :check_updates
    pkgs_to_check << DistroPackage::Nix.list[pkgname]
  end

  o.on("--find-unmatched-advisories", "Find security advisories which don't map to a Nix package(don't touch yet)") do
    action = :find_unmatched_advisories
  end

  o.on("--cve-update", "Fetch CVE updates") do
    do_cve_update = true
  end

  o.on("--cve-check", "Check NixPkgs against CVE database") do
    action = :cve_check
  end

  o.on("--coverage", "list NixPkgs packages which have (no) update coverage") do
    action = :coverage
  end

  o.on("-h", "--help", "Show this message") do
    puts o
    exit
  end

  o.parse(ARGV)
end

distros_to_update.each do |distro|
  log.debug distro.generate_list.inspect
end

if action == :coverage

  coverage = {}
  DistroPackage::Nix.packages.each do |pkg|
    coverage[pkg] = Updaters.map{ |updater| (updater.covers?(pkg) ? 1 : 0) }.reduce(0, :+)
  end

  DB.transaction do
    DB.create_table!(:estimated_coverage) do
      String :pkg_attr, :unique => true, :primary_key => true
      Integer :coverage
    end

    csv_string = CSV.generate do |csv|
      csv << ['Attr', 'Name','Version', 'Coverage']
      coverage.each do |pkg, cvalue|
        csv << [ pkg.internal_name, pkg.name, pkg.version, cvalue ]
        DB[:estimated_coverage] << { :pkg_attr => pkg.internal_name, :coverage => cvalue }
      end
    end
  end
  File.write(csv_report_file, csv_string) if csv_report_file

  covered = coverage.keys.select { |pkg| coverage[pkg] > 0 }
  notcovered = coverage.keys.select { |pkg| coverage[pkg] <=0 }
  puts "Covered #{covered.count} packages: #{covered.map{|pkg| "#{pkg.name} #{coverage[pkg]}"}.inspect}"
  puts "Not covered #{notcovered.count} packages: #{notcovered.map{|pkg| "#{pkg.name}:#{pkg.version}"}.inspect}"
  hard_to_cover = notcovered.select{ |pkg| pkg.url == nil or pkg.url == "" or pkg.url == "none" }
  puts "Hard to cover #{hard_to_cover.count} packages: #{hard_to_cover.map{|pkg| "#{pkg.name}:#{pkg.version}"}.inspect}"


elsif action == :check_updates

  Updaters.each do |updater|
    DB.transaction do

      DB.create_table!(updater.friendly_name) do
        String :pkg_attr, :unique => true, :primary_key => true
        String :version
      end

      pkgs_to_check.each do |pkg|
        new_ver = updater.newest_version_of pkg
        if new_ver
          puts "#{pkg.internal_name}/#{pkg.name}:#{pkg.version} " +
               "has new version #{new_ver} according to #{updater.friendly_name}"
          DB[updater.friendly_name] << { :pkg_attr => pkg.internal_name, :version => new_ver }
        end
      end

    end
  end

  # generate CSV report
  csv_string = CSV.generate do |csv|
    csv << ([ 'Attr', 'Name','Version', 'Coverage' ] + Updaters.map(&:name))

    pkgs_to_check.each do |pkg|
      report_line = [ pkg.internal_name, pkg.name, pkg.version ]
      report_line << Updaters.map{ |updater| (updater.covers?(pkg) ? 1 : 0) }.reduce(0, :+)

      Updaters.each do |updater|
        record = DB[updater.friendly_name][:pkg_attr => pkg.internal_name]
        report_line << ( record ? record[:version] : nil )
      end

      csv << report_line
    end
  end
  File.write(csv_report_file, csv_string) if csv_report_file

elsif action == :check_pkg_version_match

  DB.transaction do
    DB.create_table!(:version_mismatch) do
      String :pkg_attr, :unique => true, :primary_key => true
    end

    DistroPackage::Nix.packages.each do |pkg|
      unless Updater.versions_match?(pkg)
        puts pkg.serialize 
        DB[:version_mismatch] << pkg.internal_name
      end
    end
  end

elsif action == :find_unmatched_advisories

  known_safe = [
    # these advisories don't apply because they have been checked to refer to packages that don't exist in nixpgs
    "GLSA-201210-02",
  ]
  SecurityAdvisory::GLSA.list.each do |glsa|
    nixpkgs = glsa.matching_nixpkgs
    if nixpkgs
      log.info "Matched #{glsa.id} to #{nixpkgs.internal_name}"
    elsif known_safe.include? glsa.id
      log.info "Skipping #{glsa.id} as known safe"
    else
      log.warn "Failed to match #{glsa.id} #{glsa.packages}"
    end
  end
end


SecurityAdvisory::CVE.fetch_updates if do_cve_update


if action == :cve_check

  def sorted_hash_to_s(tokens)
    tokens.keys.sort{|x,y| tokens[x] <=> tokens[y] }.map{|t| "#{t}: #{tokens[t]}"}.join("\n")
  end

  list = SecurityAdvisory::CVE.list

  products = {}
  product_to_cve = {}
  list.each do |entry|
    entry.packages.each do |pkg|
      (supplier, product, version) = SecurityAdvisory::CVE.parse_package(pkg)
      pname = "#{product}"
      products[pname] = Set.new unless products[pname]
      products[pname] << version

      fullname = "#{product}:#{version}"
      product_to_cve[fullname] = Set.new unless product_to_cve[fullname]
      product_to_cve[fullname] << entry.id
    end
  end
  puts "products #{products.count}: #{products.keys.join("\n")}"

  products.each_pair do |product, versions|
    versions.each do |version|
      log.warn "can't parse version #{product} : #{version}" unless version =~ /^\d+\.\d+\.\d+\.\d+/ or version =~ /^\d+\.\d+\.\d+/ or version =~ /^\d+\.\d+/ or version =~ /^\d+/ 
    end
  end

  tokens = {}
  products.keys.each do |product|
    product.scan(/(?:[a-zA-Z]+)|(?:\d+)/).each do |token|
      tokens[token] = ( tokens[token] ? (tokens[token] + 1) : 1 )
    end
  end
  log.info "token counts \n #{sorted_hash_to_s(tokens)} \n\n"

  selectivity = {}
  tokens.keys.each do |token|
    selectivity[token] = DistroPackage::Nix.packages.count do |pkg|
      pkg.internal_name.include? token or pkg.name.include? token
    end
  end
  log.info "token selectivity \n #{sorted_hash_to_s(selectivity)} \n\n"

  false_positive_impact = {}
  tokens.keys.each{ |t| false_positive_impact[t] = tokens[t] * selectivity[t] }
  log.info "false positive impact \n #{sorted_hash_to_s(false_positive_impact)} \n\n"

  product_blacklist = Set.new [ '.net_framework', 'iphone_os', 'nx-os',
    'unified_computing_system_infrastructure_and_unified_computing_system_software',
    'bouncycastle:legion-of-the-bouncy-castle-c%23-crytography-api', # should be renamed instead of blocked
  ]

  DB.transaction do

  DB.create_table!(:cve_match) do
    String :pkg_attr#, :primary_key => true
    String :product
    String :version
    String :CVE
  end

  products.each_pair do |product, versions|
    next if product_blacklist.include? product
    tk = product.scan(/(?:[a-zA-Z]+)|(?:\d+)/).select do |token|
      token.size != 1 and not(['the','and','in','on','of','for'].include? token)
    end

    pkgs =
      DistroPackage::Nix.packages.select do |pkg|
        score = tk.reduce(0) do |score, token|
          res = ((pkg.internal_name.include? token or pkg.name.include? token) ? 1 : 0)
          res *= ( selectivity[token]>20 ? 0.51 : 1 )
          score + res
        end
        ( score >= 1 or ( tk.size == 1 and score >= 0.3 ) )
      end.to_set

    versions.each do |version|
      if version =~ /^\d+\.\d+\.\d+\.\d+/ or version =~ /^\d+\.\d+\.\d+/ or version =~ /^\d+\.\d+/ or version =~ /^\d+/ 
        v = $&
        pkgs.each do |pkg|
          next if product == 'perl' and pkg.internal_name.start_with? 'perlPackages.'
          next if product == 'python' and (pkg.internal_name =~ /^python\d\dPackages\./ or pkg.internal_name.start_with? 'pythonDocs.')
          if pkg.version =~ /^\d+\.\d+\.\d+\.\d+/ or pkg.version =~ /^\d+\.\d+\.\d+/ or pkg.version =~ /^\d+\.\d+/ or pkg.version =~ /^\d+/ 
            v2 = $&

          #if (pkg.version == v) or (pkg.version.start_with? v and not( ('0'..'9').include? pkg.version[v.size]))
            if v == v2
              fullname = "#{product}:#{version}"
              product_to_cve[fullname].each do |cve|
                DB[:cve_match] << {
                  :pkg_attr => pkg.internal_name,
                  :product => product,
                  :version => version,
                  :CVE => cve
                }
              end
              log.warn "match #{product_to_cve[fullname].inspect}: #{product}:#{version} = #{pkg.internal_name}/#{pkg.name}:#{pkg.version}"
            end
          end
        end
      end
    end
  end

  end

end
