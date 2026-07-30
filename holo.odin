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

import "core:sort"
import "core:mem"
import "core:relative"
import "core:testing"
import "core:time"
import "core:encoding/hxa"
import "shared/tinyobj"
import gltf "shared/glTF2"
import "base:runtime"
import "core:os"

import "core:bytes"
import "core:strings"
import "core:fmt"

import "core:image"
import "core:image/bmp"
import "core:image/jpeg"
import "core:image/netpbm"
import "core:image/png"
import "core:image/qoi"
import "core:image/tga"

@(private) print := fmt.println

converter_obj :: proc(data: tinyobj.OBJ, dir: string, cfg: Config, allocator := context.allocator) -> (out: hxa.File) {
	verb := proc(args: ..any, sep := " ", flush := true) -> int { return 0 }
	if cfg.verbose == true {
		verb = print
	}

	context.allocator = allocator // Is that legal?
	out.allocator = allocator
	nodes := make([dynamic]hxa.Node)

	vertex := make(hxa.Layer_Stack, 4)
	vertex[0] = {
		name = hxa.CONVENTION_HARD_BASE_VERTEX_LAYER_NAME,
		components = hxa.CONVENTION_HARD_BASE_VERTEX_LAYER_COMPONENTS,
		data = make([]f32le, len(data.attrib.faces)*3)
	} 
	vertex[1] = {
		name = hxa.CONVENTION_SOFT_LAYER_NORMALS,
		components = 3,
		data = make([]f32le, len(data.attrib.faces)*3)
	}
	vertex[2] = {
		name = "uv",
		components = 2,
		data = make([]f32le, len(data.attrib.faces)*2)
	}
	vertex[3] = {
		name = "mat_idx",
		components = 2,
		data = make([]i32le, len(data.attrib.faces)*2)
	}

	// I know, thats not's C..
	position_index, 
	normals_index, 
	uv_index, 
	tex_index, 
	vertex_index3,
	vertex_index2: int

	normals_len := len(data.attrib.normals)
	uv_len 			:= len(data.attrib.texcoords)
	mat_len 		:= len(data.materials)
	faces_len 	:= len(data.attrib.faces)
	matid_len		:= len(data.attrib.material_ids)


	if cfg.verbose {
		print("	","Materials: ", 			 len(data.materials))
		print("	","Material IDs: ",    len(data.attrib.material_ids))
		print("	","Faces: ",           len(data.attrib.faces))
		print("	","Faces Num Verts: ", len(data.attrib.face_num_verts))
		print("	","Vertices: ",        len(data.attrib.vertices))
		print("	","Normals: ",         len(data.attrib.normals))
		if len(data.attrib.texcoords) > 0 {
			print("	","Texcoords: ",     len(data.attrib.texcoords))
		}
	}
	/*
	print(data.materials)
	if len(data.materials) > 0 {
		if len(data.materials) > 100 {
		}
			// print("HEY, THATS WEIRD!!!")
			uniqueNumbers : [10000]i32le
			for m_id in data.attrib.material_ids {
				uniqueNumbers[m_id] += 1
			}
			for unique, unique_i in uniqueNumbers {
				if unique > 0 {
					print("[",unique_i,"]", unique, sep="")
				}
			}
			// print(data.materials[50:51])
	}
	*/

	matID_used : [dynamic]i32le
	matID_past : i32le = -1
		
	{ verb("-Process Vertices")
	mat_id : i32le
	uv_flip : f32le = cfg.uv_flip ? 1 : 0
	for f, f_i in data.attrib.faces {
		tex_index = int(f32(f_i) / 3.0)

		vertex_index3 = f_i * 3
		vertex_index2 = f_i * 2
	
		vertex[0].data.([]f32le)[vertex_index3    ],
		vertex[0].data.([]f32le)[vertex_index3 + 1],
		vertex[0].data.([]f32le)[vertex_index3 + 2] = expand_values(data.attrib.vertices[f.v_idx])

		if normals_index < normals_len && f.vn_idx != tinyobj.INVALID_INDEX_LE {
			vertex[1].data.([]f32le)[vertex_index3    ],
			vertex[1].data.([]f32le)[vertex_index3 + 1],
			vertex[1].data.([]f32le)[vertex_index3 + 2] = expand_values(data.attrib.normals[f.vn_idx])
		}

		if f.vt_idx != tinyobj.INVALID_INDEX_LE {
			vertex[2].data.([]f32le)[vertex_index2    ] = data.attrib.texcoords[f.vt_idx].x
			vertex[2].data.([]f32le)[vertex_index2 + 1] = uv_flip - data.attrib.texcoords[f.vt_idx].y
		}
		
		
		if tex_index < matid_len {
			mat_id = data.attrib.material_ids[tex_index]

			if mat_id != matID_past {
				append(&matID_used, mat_id)
			}
			matID_past = data.attrib.material_ids[tex_index]
		}
	}
	}; verb("-Processed")

	verb("-Make Vertex Node")
	model_node := new(hxa.Node)
	// model_node: hxa.Node
	model_node.content = hxa.Node_Geometry{
		vertex_stack = vertex,
		vertex_count = u32le(len(data.attrib.faces)),
	}
	
	model_node.meta_data = make([]hxa.Meta, 1)
	model_node.meta_data[0] = {
		name  = "type",
		value = "vertex"
	}
	verb("-Append")
	append(&nodes, model_node^)


	// if cfg.verbose {
	// 	for m, m_i in matID_used {
	// 		print("[",m_i,"]", m, sep="")
	// 	}
	// }

	matID_remap: map[i32le][2]i32le
	if mat_len > 0 { 
		verb("-Process Materials")
		node_off := len(nodes)
		img_idx: u32le
		mat: tinyobj.Material
		imagePaths_unique: map[string][2]u32le // {bool, index}
		node_metadata := make([dynamic][dynamic]hxa.Meta) // [node_index][metadata_node]
		// i know, its a little ugly, but i think will work fine for now!
		for mat_id, mat_i in matID_used {
			// handle relative index
			if mat_id < 0 { continue }
			mat = data.materials[mat_id]
			if len(mat.diffuse_texname) <= 0 { continue }
	
			if imagePaths_unique[mat.diffuse_texname].x == 0 {
				verb("Mat ", mat_i, ": ", mat.name, sep="")
		
				// read texture
				img_options := image.Options{.alpha_add_if_missing}
				diff_path, _ := os.join_path({dir,mat.diffuse_texname}, allocator)
				diff_path, _ = os.replace_path_separators(diff_path, os.Path_Separator, allocator)
				
				diff_img, read_err := image.load_from_file(diff_path, img_options)
				if read_err == .Unable_To_Read_File {
					verb(read_err, " - Image Fallback")
					files, folder_err := os.read_directory_by_path(dir, 0, allocator)
					if folder_err != os.General_Error.None {
						continue
					}
					str := strings.to_upper_snake_case(mat.diffuse_texname)
					read_err : image.Error
					for f in files {
						str_entry := strings.to_upper_snake_case(f.name)
						if str_entry == str {
							diff_img, read_err = image.load_from_file(f.fullpath, img_options)
							break
						}
					}
					for f in files {
						str_entry := os.stem(f.name)
						diff_img, read_err = image.load_from_file(f.fullpath, img_options)
						break
					}
					if read_err != image.General_Image_Error.None {
						verb(read_err)
						continue
					}
				}
		
				verb("-Make Image Node")
				tex := new(hxa.Node)
				
				img_layers := make(hxa.Layer_Stack, 1)
				img_layers[0] = {
					components = 4,
					name = hxa.CONVENTION_SOFT_ALBEDO,
					data = bytes.buffer_to_bytes(&diff_img.pixels)
				}
		
				tex.content = hxa.Node_Image{
					resolution = {u32le(diff_img.width), u32le(diff_img.height), 1},
					type = .Image_2D,
					image_stack = img_layers
				}
				metadata := make([dynamic]hxa.Meta)
				
				append(&metadata, hxa.Meta{
					name = "type",
					value = "texture"
				})
				append(&metadata, hxa.Meta{
					name = hxa.CONVENTION_SOFT_LAYER_MATERIAL_ID,
					value = mat_node(&mat)
				})
				
				append(&node_metadata, metadata)
				append(&nodes, tex^)
				verb("-Append")
	
				matID_remap[i32le(mat_id)] = {i32le(img_idx), 2}
				imagePaths_unique[mat.diffuse_texname] = {1,img_idx}
				img_idx += 1
			} else {
				if matID_remap[i32le(mat_id)].x == 0 {
					append(&node_metadata[imagePaths_unique[mat.diffuse_texname].y], hxa.Meta{
						name = hxa.CONVENTION_SOFT_LAYER_MATERIAL_ID,
						value = mat_node(&mat)
					})
	
					matID_remap[i32le(mat_id)] = {i32le(imagePaths_unique[mat.diffuse_texname].y), i32le(len(node_metadata[imagePaths_unique[mat.diffuse_texname].y]))}
				}
			}
		}
		
		for nm, nm_i in node_metadata {
			nodes[node_off + nm_i].meta_data = nm[:]
		}
	
		if cfg.verbose == false {
			print("Node Metadata Length: ",len(node_metadata[:]))
			for nmt, nmt_i in node_metadata {
				print(" Meta ",nmt_i,": ",len(nmt[:]), sep="")
			}
			for mid_i, mid in matID_remap {
				print(" Remap ",mid_i,": ",mid, sep="")
			}
		} // cfg.verbose
	} // Process Materials

	verb("-Finalize Materials")
	for idx in 0..<faces_len {
		tex_index = int(f32(idx) / 3.0)
		if tex_index < matid_len {
			vertex_index2 = idx * 2
			vertex[3].data.([]i32le)[vertex_index2		],
			vertex[3].data.([]i32le)[vertex_index2 + 1] = expand_values(matID_remap[data.attrib.material_ids[tex_index]])
		} else {
			break
		}
	}
	
	// probably that's not needed
	// vertex_count: u32le
	// for k in vertex {
	// 	l: u32le
	// 	switch v in k.data {
	// 		case []u8:
	// 			l = u32le(len(k.data.([]u8)))
	// 		case []i32le:
	// 			l = u32le(len(k.data.([]i32le)))
	// 		case []f32le:
	// 			l = u32le(len(k.data.([]f32le)))
	// 		case []f64le:
	// 			l = u32le(len(k.data.([]f64le)))
	// 	}
	// 	vertex_count += u32le(k.components)
	// }

	out.nodes = nodes[:]
	// out.nodes[0] = model_node^
	// for i in 0..<nodes_total {
	// 	out.nodes[i+1] = image_list[i]
	// }
	
	// out.internal_node_count = u32le(len(out.nodes))
	// delete_dynamic_array(nodes)

	// print(data.attrib.texcoords)
	// print(uv_lencur, uv_len)
	return
}
converter_gltf :: proc(data: ^gltf.Data, dir: string, cfg: Config, allocator := context.allocator) -> (out: hxa.File) {
	context.allocator = allocator
	nodes := make([dynamic]hxa.Node)

	// every mesh is a object/node(hxa)
	for m, i in data.meshes {		
		print(
			"\n==================\n",
			"-- ",m.name," --\n",
			"Primitives Amount: ",len(m.primitives),"\n",
			"Mesh Index: ",i,
			"\n==================\n", sep="")

		p_i3,
		p_i2: int
		for p, p_i in m.primitives {
			p_i3 = p_i * 3
			p_i2 = p_i * 2
			
			// vertex := make(hxa.Layer_Stack, 4, allocator)
			// vertex[0] = {
			// 	name = hxa.CONVENTION_HARD_BASE_VERTEX_LAYER_NAME,
			// 	components = hxa.CONVENTION_HARD_BASE_VERTEX_LAYER_COMPONENTS,
			// 	data = make([]f32le, len(obj.attrib.faces)*3, allocator)
			// }
			// vertex[1] = {
			// 	name = hxa.CONVENTION_SOFT_LAYER_NORMALS,
			// 	components = 3,
			// 	data = make([]f32le, len(obj.attrib.faces)*3, allocator)
			// }
			// vertex[2] = {
			// 	name = "uv",
			// 	components = 2,
			// 	data = make([]f32le, len(obj.attrib.faces)*2, allocator)
			// }
			// vertex[3] = {
			// 	name = "tex_i",
			// 	components = 1,
			// 	data = make([]i32le, len(obj.attrib.faces), allocator)
			// }

			// print(p.attributes)
			position := gltf.buffer_slice(data,p.attributes["POSITION"])
			normal := gltf.buffer_slice(data,p.attributes["NORMAL"])
			texCoord_0 := gltf.buffer_slice(data,p.attributes["TEXCOORD_0"])
			
			print(len(position.([][3]f32)))
			print(len(normal.([][3]f32)))
			print(len(texCoord_0.([][2]f32)))
			print(position.([][3]f32))
			
			


			// model_node := new(hxa.Node, allocator)
			// // model_node: hxa.Node
			// model_node.content = hxa.Node_Geometry{
			// 	vertex_stack = vertex,
			// 	vertex_count = u32le(len(obj.attrib.faces)),
			// }
			
			// model_node.meta_data = make([]hxa.Meta, 1)
			// model_node.meta_data[0] = {
			// 	name = "type",
			// 	value = "vertex"
			// }
			// append(&nodes, model_node^)
		}

		//mesh primitive index ->
		//acessor index ->
		//buffer view index ->
		//buffer = the beautiful data

		// mesh primitives is weird, each primitive is a texture index
		// merge all togetter or split? give that as a option?

	}

	// for data_byte in data.buffers[meshPos_buffView.buffer].uri.([]byte)[mesh_off:mesh_len] {
	// 	print(data_index)
	// 	data_index = (data_index + 1) % max()
	// }
	out.nodes = nodes[:]
	return
}


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
				data := tinyobj.parse_obj(string(file), dir, tinyobj.FLAG_TRIANGULATE)
				defer tinyobj.destroy(&data)
				
				verb("-Convert")
				out = converter_obj(data, dir, cfg)

				return
			case ".gltf", ".glb":
				/*
				verb("-Parse GLTF/GLB")
		    options := gltf.Options {
	        delete_content = true,
	        gltf_dir       = dir,
					is_glb				 = ext == ".glb"
		    }
				data, parse_err := gltf.parse(file, options)

				verb("-Convert")
				out = converter_gltf(data, dir, cfg)
				*/
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

// Convert a material from tinyobj to a nested hxa node 
@(private)
mat_node :: proc(
	mat: ^tinyobj.Material, 
	alloc := context.allocator
	) -> (meta: []hxa.Meta) {	
	meta = make([]hxa.Meta, 17, alloc)
	meta[0] = {
		name = "name",
		value = mat.name,
	}
	meta[1] = {
		name = "ambient",
		value = mat.ambient[:],
	}
	meta[2] = {
		name = "diffuse",
		value = mat.diffuse[:],
	}
	meta[3] = {
		name = "specular",
		value = mat.specular[:],
	}
	meta[4] = {
		name = "transmittance",
		value = mat.transmittance[:],
	}
	meta[5] = {
		name = "emission",
		value = mat.emission[:],
	}
	meta[6] = {
		name = "shininess",
		value = []f64le{mat.shininess},
	}
	meta[7] = {
		name = "ior",
		value = []f64le{mat.ior},
	}
	meta[8] = {
		name = "dissolve",
		value = []f64le{mat.dissolve},
	}
	meta[9] = {
		name = "illum",
		value = []i64le{mat.illum},
	}
	meta[10] = {
		name = "ambient_texname",
		value = mat.ambient_texname,
	}
	meta[11] = {
		name = "diffuse_texname",
		value = mat.diffuse_texname,
	}
	meta[12] = {
		name = "specular_texname",
		value = mat.specular_texname,
	}
	meta[13] = {
		name = "specular_highlight_texname",
		value = mat.specular_highlight_texname,
	}
	meta[14] = {
		name = "bump_texname",
		value = mat.bump_texname,
	}
	meta[15] = {
		name = "displacement_texname",
		value = mat.displacement_texname,
	}
	meta[16] = {
		name = "alpha_texname",
		value = mat.alpha_texname,
	}
	return
}
