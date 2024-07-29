require 'optparse'
require 'fileutils'
require 'yaml'

HERE = File.dirname(__FILE__)
CONFIG_PATH = File.absolute_path(File.join(HERE, './config.yml'))
config = {}
if File.exists?(CONFIG_PATH)
	config = YAML.load(File.read(CONFIG_PATH))
end

options = {}
OptionParser.new do |opts|
	opts.banner = "Usage: ruby find-audio.rb [options]"

	opts.on("-sSYMBOLS", "--symbols=SYMBOLS", "Symbols to search") do |v|
		options[:symbols] = v
	end

	opts.on("-wWORDS", "--words=WORDS", "Words to search") do |v|
		options[:full_words] = v
	end

	opts.on("-nNAME", "--name=NAME", "Name of the results folder") do |v|
		options[:name] = v
	end

	opts.on("-oOUTPUT_FOLDER", "--output-folder=OUTPUT_FOLDER", "Folder to save results") do |v|
		options[:output_folder] = v
	end

	opts.on("-fFOLDERS", "--folders=FOLDERS", "Folder to search") do |v|
		options[:folder] = v
	end

	opts.on("-d", "--dry", "Don't copy anything") do |v|
		options[:dry] = v
	end

	opts.on("-h", "--help", "Prints this help") do
		puts opts
		exit
	end
end.parse!

def split_folders(text)
	return nil if text.nil?
	text.split(/\s+,\s+/)
end

def split_symbols(text)
	text.split(',').map{|s| s.strip.downcase.gsub(/\s+/, ' ')}.uniq
end

def parse_symbols(text)
	blank_pattern = '[-\s_]*'
	split_symbols(text).map{|s| s.gsub(' ', blank_pattern)}
end

def generate_pattern_for(options)
	full_words = parse_symbols(options[:full_words]).map{|w| "(^|[^a-z])#{w}($|[^a-z])"}
	symbols = parse_symbols(options[:symbols])
	pattern = [*full_words, *symbols].join('|')
	return "(#{pattern})"
end

def generate_name_for(options)
	full_words = split_symbols(options[:full_words])
	symbols = split_symbols(options[:symbols])
	name = [*full_words, *symbols].join('-').gsub(/[^0-9A-Za-z]/, '')
	return "#{name[0..30]}#{name[-30..-1]}"
end

options[:full_words] ||= ''
options[:symbols] ||= ''
folders = split_folders(options[:folders]) || config['folders'] || ['.']
options[:output_folder] ||= './find-results/'
options[:name] ||= generate_name_for(options)


pattern = generate_pattern_for(options)
full_output_folder = File.join(options[:output_folder], options[:name])
puts "Options: #{options.inspect}"
puts "Searching for #{pattern.inspect}"

raw_paths = folders.flat_map do |folder|
	folder_pattern = File.join(folder, "**/*.{wav,mp3,flac,m4a,ogg,aiff,aif,wma,aac}")
	puts "Searching in: #{folder_pattern}"
	Dir.glob(folder_pattern, File::FNM_CASEFOLD)
end
puts "All files Count: #{raw_paths.size}"

paths = raw_paths.find_all{|path| path.match(/#{pattern}/i)}.map{|path| File.absolute_path(path)}.compact.uniq
puts "Files found: #{paths.size}"
#`vlc #{paths.map{|path| '"' + path + '"'}.join(" ")}`

FileUtils.mkdir_p(full_output_folder)

abs_folders = folders.map{|folder| File.absolute_path(folder)}

FILEPREFIX_SIZE = 8
FILEPREFIX_MAX_FOLDERS = 3
paths.each do |path|
	begin
		path_suffix = File.dirname(path)
		abs_folders.each do |abs_folder|
			path_suffix = path_suffix.gsub(/^#{abs_folder}/, '')
		end
		prefix_folders = path_suffix.split(File::SEPARATOR)
		included_count = [prefix_folders.size, FILEPREFIX_MAX_FOLDERS].min
		chars_per_folder = [FILEPREFIX_SIZE / included_count] * included_count
		(FILEPREFIX_SIZE % included_count).times{|inx| chars_per_folder[-inx-1] += 1}
		prefix = prefix_folders
			.last(included_count)
			.map do |folder|
				original_folder = folder
				folder = folder.downcase.gsub(/[^0-9a-z]/, '')
				max_offset = folder.size - chars_per_folder.first
				offset = max_offset / 3
				prefix = folder[offset...(offset+chars_per_folder.shift)]
				# puts "Folder: #{original_folder} Prefix: #{prefix}"
				prefix
			end
			.join('')
		inx = 0
		result_path = nil
		while result_path.nil? || File.exists?(result_path)
			new_filename = inx.zero? ? File.basename(path) : File.basename(path, File.extname(path)) + "-#{inx}" + File.extname(path)
			new_filename = [prefix, new_filename].join('-')
			result_path = File.join(full_output_folder, new_filename)
			inx += 1
		end
		if options[:dry]
			puts "[DRY] #{path} => #{result_path}"
		else
			FileUtils.cp(path, result_path)
		end
	rescue => e
	    puts "Ignoring: #{path} Error: #{e.message}" 
	end
end