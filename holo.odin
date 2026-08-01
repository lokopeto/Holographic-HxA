/*
MIT NON-AI License

Copyright (c) 2026 lokopeto
Permission is hereby granted, free of charge, to any person obtaining a copy of the software and associated documentation files (the "Software"),
to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions.

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

In addition, the following restrictions apply:

1. The Software and any modifications made to it may not be used for the purpose of training or improving machine learning algorithms,
including but not limited to artificial intelligence, natural language processing, or data mining. This condition applies to any derivatives,
modifications, or updates based on the Software code. Any usage of the Software in an AI-training dataset is considered a breach of this License.

2. The Software may not be included in any dataset used for training or improving machine learning algorithms,
including but not limited to artificial intelligence, natural language processing, or data mining.

3. Any person or organization found to be in violation of these restrictions will be subject to legal action and may be held liable
for any damages resulting from such use.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE
OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

package holo

import "core:reflect"
import "core:sort"
import "core:mem"
import "core:relative"
import "core:testing"
import "core:time"
import "core:encoding/hxa"
import "base:runtime"
import "core:os"
import gltf "shared/glTF2"

import "core:bytes"
import "core:strings"
import "core:strconv"
import "core:fmt"

import "core:image"
import "core:image/bmp"
import "core:image/jpeg"
import "core:image/netpbm"
import "core:image/png"
import "core:image/qoi"
import "core:image/tga"

@(private) print := fmt.println

Error :: enum {
	None,
	Invalid_File,
}
Config :: struct {
	verbose: bool,
	uv_flip: bool,
}
DEFAULT_CONFIG :: Config{
	verbose = false,
	uv_flip = false,
}
converter :: proc(
		path: string,
		cfg: Config = DEFAULT_CONFIG,
		allocator := context.allocator
	) -> ( out: hxa.File, err: Error ) {
	verb := proc(args: ..any, sep := " ", flush := true) -> int { return 0 }
	if cfg.verbose == true { verb = print }
	context.allocator = allocator
	dir, ext := os.dir(path), os.ext(path)
	ext = strings.to_lower(ext)
	file, file_err := os.read_entire_file(path, allocator)
	
	if file_err == os.General_Error.None {
		verb("Path:", path)
		verb("Dir/Ext:", dir, ext)
		switch ext {
			case ".obj":
				verb("-Parse OBJ")
				
				verb("-Convert")
				out = converter_obj(file, dir, cfg)

				return
			case ".gltf", ".glb":
				verb("-Parse GLTF/GLB")
		    options := gltf.Options {
	        delete_content = true,
	        gltf_dir       = dir,
					is_glb				 = ext == ".glb"
		    }
				data, parse_err := gltf.parse(file, options)

				verb("-Convert")
				out = converter_gltf(data, dir, cfg)
				return
			case:
				verb("File Error:", "Invalid Ext")
				delete(file[:])
				return out, .Invalid_File
		}
	}

	verb("File Error:", file_err)
	delete(file[:])
	return out, .Invalid_File
}

@(test)
main_test :: proc (T: ^testing.T) {
	allow_recursive := #config(RECURSIVE, false)
	model_path := #config(PATH, "")
	if model_path == "" {
		allow_recursive = true
		model_path = "The-3D-Samples"
	}
	

	if allow_recursive {
		walk := os.walker_create(model_path)
		for w in os.walker_walk(&walk) {
			if w.type == .Regular {
				wd, _ := os.get_working_directory(context.temp_allocator)
				relative_path, _ := os.get_relative_path(wd,w.fullpath, context.temp_allocator)
				loadModel_test(T,relative_path)
				free_all(context.temp_allocator)
			}
		}
		os.walker_destroy(&walk)
	} else {
		loadModel_test(T,model_path)
	}
	
	make_folder_recursive :: proc(path_out, path: string, alloc := context.temp_allocator) -> string {
		path_split, _ := strings.split_after_n(os.dir(path), os.Path_Separator_String, 2, alloc)
		path_split[0] = path_out
		out := strings.join(path_split, os.Path_Separator_String, alloc)
		os.make_directory_all(out)
		return out
	}
	
	loadModel_test :: proc(T: ^testing.T,path: string) {
		context.allocator = context.temp_allocator
		readobj_time,
		conversion_time,
		read_time   				 : time.Time
		readobj_duration,
		conversion_duration,
		read_duration   		 : time.Duration
	
		conversion_time = time.now()
		
		print("-- Converter --")
		modelhxa, model_err := converter(path, {
			verbose = true,
			uv_flip = true
		}, context.allocator);


		if model_err != .None { return }

		
		defer hxa.file_destroy(modelhxa)
	
		out_path := make_folder_recursive("out", path)
		out_file := strings.join(
			{	
				out_path, 
					os.Path_Separator_String, 
				os.base(path[:len(path) - len(os.long_ext(path))]),
					".hxa"
			},
			sep="")
		print("Output Path:",out_file)
		
		write_err := hxa.write_to_file(out_file, modelhxa)
		conversion_duration	= time.diff(conversion_time, time.now())
		print("Duration:", conversion_duration,", Status: ", write_err, "\n", sep="")
		
		read_time = time.now()
		out_read, read_err := hxa.read_from_file(out_file, true)
		defer hxa.file_destroy(out_read)

		read_duration	= time.diff(read_time, time.now())

		testing.expect(T, out_read.magic_number == hxa.MAGIC_NUMBER)
		// testing.expect(T,out_read.internal_node_count > 0)
		testing.expect(T, out_read.version == hxa.LATEST_VERSION)
		testing.expect(T, len(out_read.backing) > 0)

		testing.expect(T, len(out_read.nodes) == len(modelhxa.nodes))
		testing.expect(T, read_err == .None)

		print("-- Read --")
		print("Node Length:",len(out_read.nodes))
		print("Internal Node Count:",out_read.internal_node_count)
		print("Duration:", read_duration, ", Status: ", read_err, sep="")
		print("----")
	}
}


//Procs that no one cares:

ImageLoadError :: enum {
	None,
	File_Load_Error,
	Image_Decoding_Error,
}
img_load :: proc(dir, path: string, allocator := context.allocator) -> (img: ^image.Image, err: ImageLoadError) {
	img_options := image.Options{.alpha_add_if_missing}
	img_path, _ := os.join_path({dir,path}, allocator)
	img_path, _ = os.replace_path_separators(img_path, os.Path_Separator, allocator)
	
	read_err: image.Error
	img, read_err = image.load_from_file(img_path, img_options)
	if read_err == .Unable_To_Read_File {
		files, folder_err := os.read_directory_by_path(dir, 0, allocator)
		if folder_err != os.General_Error.None {
			err = .File_Load_Error
			return
		}
		str := strings.to_upper_snake_case(path)
		read_err : image.Error
		for f in files {
			str_entry := strings.to_upper_snake_case(f.name)
			if str_entry == str {
				img, read_err = image.load_from_file(f.fullpath, img_options)
				return
			}
		}
		for f in files {
			str_entry := os.stem(f.name)
			img, read_err = image.load_from_file(f.fullpath, img_options)
			return
		}
		if read_err != image.General_Image_Error.None {
			err = .Image_Decoding_Error
			return
		}
	}
	return
}
