require 'pp'
require 'pathname'
require 'fileutils'
require 'optparse'


class Binary

	def initialize(path)

		@path = path

	end

	def path()
		return @path
	end

	def copy!(dst)

		FileUtils.cp(@path, dst)
		@path = dst

	end

	def dylib?()
		return /.dylib$/ =~ @path ? true : false
	end

	def system_lib?()
		return Regexp.new("^/usr/lib") =~ @path ? true : false
	end

	def relative?()
		return Regexp.new("^/") =~ @path ? false : true
	end

	def dependency_libs()

		lines = Array.new
	
		IO.popen("otool -L #{@path}") do |io|
			
			io.each do |line|
				lines << line
			end
		end
		
		install_names = Array.new
		
		if lines.size != 0
			
			lines.drop(1).each do |line|
				
				if line.size != 0
					install_names << line.split[0]
				end
			end
		end
		
		return install_names

	end

	def change_install_name(before, after)
		`install_name_tool -change #{before} #{after} #{@path}`
	end

	def get_dst_path(src, dst_dir)

		src_pathname = Pathname.new(src)
		dst_pathname = Pathname.new(dst_dir)
		
		return (dst_pathname + src_pathname.basename).to_s

	end

	def get_relative_install_name(dst, executable_dir)
		return "@executable_path/" + Pathname.new(dst).relative_path_from(Pathname.new(executable_dir)).to_s
	end

	def bundle_dependency_libs(dst_dir, executable_dir, already_bundled_list)

		dependency_libs().each do |src|

			lib = Binary.new(src)

			if lib.dylib? && !lib.system_lib? && !lib.relative?

				dst = get_dst_path(src, dst_dir)
				change_install_name(src, get_relative_install_name(dst, executable_dir))

				if !already_bundled_list.include?(src) && dst != @path

					lib.copy!(dst)
					FileUtils.chmod(0664, dst)
					lib.bundle_dependency_libs(dst_dir, executable_dir, already_bundled_list)
					puts src
					already_bundled_list << src

				end
			end
		end
	end

end

def main
	
	binary_pathname = nil
	bundle_pathname = nil
	
	OptionParser.new do |opts|
		
		opts.banner = "Usage: bundlelibs.rb -x [binary filepath] -d [destination directory path]"
		opts.on("-x BINARY_PATH") do |path|
			binary_pathname = Pathname.new(path)
		end 
		opts.on("-d DESTINATION_PATH") do |path|
			bundle_pathname = Pathname.new(path)
		end
		
		opts.parse!(ARGV)
	end
	
	if not binary_pathname
		raise "binary filepath not specified"
	end
	
	if not bundle_pathname
		raise "destination directory path not specified"
	end
	
	if binary_pathname.relative?
		binary_pathname = binary_pathname.realpath
	end
	
	if not binary_pathname.exist?
		raise "binary not found"
	end
	
	if bundle_pathname.relative?
		bundle_pathname = bundle_pathname.realpath
	end
	
	bundle_pathname.mkpath

	installed_libs = Array.new

	binary = Binary.new(binary_pathname.to_s)
	binary.bundle_dependency_libs(bundle_pathname.to_s, binary_pathname.parent.to_s, installed_libs)
	
	puts "Bundled libs:"
	installed_libs.each do |name|
		puts name
	end
	
end

main()


