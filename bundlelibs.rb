require 'pp'
require 'pathname'
require 'fileutils'
require 'optparse'


def extract_install_names(binary_path)
	
	lines = Array.new
	
	IO.popen("otool -L #{binary_path}") do |io|
		
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

def get_framework_path(lib_path)
	
	match_list = lib_path.scan(/^.+\.framework/)
	return match_list.empty? ? nil : match_list[0]
	
end

def is_dylib(lib_path)
	
	return /.dylib$/ =~ lib_path ? true : false
	
end

def is_framework(lib_path)
	
	return /^.+\.framework/ =~ lib_path ? true : false
	
end

def is_lib_need_to_bundle(lib_path)
	
	# relative path
	if not Regexp.new("^/") =~ lib_path
		return false
	end
	
	#system libs 
	if Regexp.new("^/usr/lib") =~ lib_path
		return false
	end
	
	#system libs
	if Regexp.new("^/System/Library/Frameworks") =~ lib_path
		return false
	end
	
	# nothing to be done
	if /^@executable_path/ =~ lib_path
		return false
	end
	
	return true
	
end

def change_install_name_lib(binary, before, after)
	`install_name_tool -change #{before} #{after} #{binary}`
end

def change_install_name_id(binary, after)
	`install_name_tool -id #{after} #{binary}`
end

def get_relative_install_name(dst, executable_path)
	
	relative_pathname = Pathname.new(dst).relative_path_from(Pathname.new(executable_path))
	return "@executable_path/" + relative_pathname.to_s
	
end

def get_dst_path(src, dst_dir)
	
	src_pathname = Pathname.new(src)
	dst_pathname = Pathname.new(dst_dir)
	
	return (dst_pathname + src_pathname.basename).to_s
	
end

def get_dst_path_framework(src, dst_dir)
	
	src_inner_path = src.scan(Regexp.new("[^/]*\.framework.*"))[0]
	dst_pathname = Pathname.new(dst_dir)
	
	return (dst_pathname + src_inner_path).to_s
	
end

def bundle_dylib(src, dst_dir, executable_path)
	
	dst = get_dst_path(src, dst_dir)
	
	if not Pathname.new(src).exist?
		raise "dylib not found"
	end
	
	if Pathname.new(dst).exist?
		raise "dylib already exists in destination"
	end
	
	FileUtils.cp(src, dst)
	FileUtils.chmod(0644, dst)
	change_install_name_id(dst, get_relative_install_name(dst, executable_path))
	
end

def bundle_framework(src, dst_dir, executable_path)
	
	dst = get_dst_path_framework(src, dst_dir)
	
	if not Pathname.new(get_framework_path(src)).exist?
		raise "framework not found"
	end
	
	if Pathname.new(get_framework_path(dst)).exist?
		raise "framework already exists"
	end
	
	FileUtils.cp_r(get_framework_path(src), dst_dir)
	FileUtils.chmod(0644, dst)
	change_install_name_id(dst, get_relative_install_name(dst, executable_path))
	
end

$already_bundled_list = Array.new

def is_already_included(name)
	
	$already_bundled_list.each do |bundled|
		
		if bundled == name
			return true
		end
		
	end
	
	return false
	
end

def add_already_included_lib(name)
	
	$already_bundled_list << name
	
end

$bundled_lib_src_names = []

def bundle_used_libs(binary, bundle_dir, executable_path)
	
	extract_install_names(binary).each do |name|
		
		if is_lib_need_to_bundle(name)
			
			if is_dylib(name)
				
				$bundled_lib_src_names = $bundled_lib_src_names | [name]
				
				dst_name = get_dst_path(name, bundle_dir)
				change_install_name_lib(binary, name, get_relative_install_name(dst_name, executable_path))
				
				if not is_already_included(dst_name)
					
					bundle_dylib(name, bundle_dir, executable_path)
					add_already_included_lib(dst_name)
					bundle_used_libs(dst_name, bundle_dir, executable_path)
					
				end
				
			end
			
			if is_framework(name)
				
				$bundled_lib_src_names = $bundled_lib_src_names | [name]
				
				dst_name = get_dst_path_framework(name, bundle_dir)
				change_install_name_lib(binary, name, get_relative_install_name(dst_name, executable_path))
				
				if not is_already_included(dst_name)
					
					bundle_framework(name, bundle_dir, executable_path)
					add_already_included_lib(dst_name)
					bundle_used_libs(dst_name, bundle_dir, executable_path)
	
				end
								
			end
		end
	end
	
end

def main
	
	app_pathname = nil
	bundle_pathname = nil
	
	OptionParser.new do |opts|
		
		opts.banner = "Usage: bundlelibs.rb -x [binary filepath] -d [destination directory path]"
		opts.on("-x BINARY_PATH") do |path|
			app_pathname = Pathname.new(path)
		end 
		opts.on("-d DESTINATION_PATH") do |path|
			bundle_pathname = Pathname.new(path)
		end
		
		opts.parse!(ARGV)
	end
	
	if not app_pathname
		raise "binary filepath not specified"
	end
	
	if not bundle_pathname
		raise "destination directory path not specified"
	end
	
	if app_pathname.relative?
		app_pathname = app_pathname.realpath
	end
	
	if not app_pathname.exist?
		raise "binary not found"
	end
	
	if bundle_pathname.relative?
		bundle_pathname = bundle_pathname.realpath
	end
	
	bundle_pathname.mkpath
	
	bundle_used_libs(app_pathname.to_s, bundle_pathname.to_s, app_pathname.parent.to_s)
	
	puts "Bundled libs:"
	$bundled_lib_src_names.each do |name|
		puts name
	end
	
end

main()


