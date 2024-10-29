module Emissary

class MapUtils

    # cache this data
    @@hexsizes = nil

    # get coords adjacent to this hex
    def self.adjacent_coords(coord)
        coords = [
           {:x => coord[:x]-1, :y => coord[:y]},
           {:x => coord[:x], :y => coord[:y]+1},
           {:x => coord[:x]+1, :y => coord[:y]+1},
           {:x => coord[:x]+1, :y => coord[:y]},
           {:x => coord[:x], :y => coord[:y]-1},
           {:x => coord[:x]-1, :y => coord[:y]-1}
        ]
        coords
    end

    # gets the adjacent coords
    def self.adjacent(coord, size)
      coords = self.adjacent_coords(coord)
      coords.delete_if { | c |
         !self.mapcontains(size, c)
      }
      coords
   end

    # random coord
    def self.randcoord(size)
        coords = self.mapcoords(size).sample
    end

    # util for getting generic hex data
    def self.hexsizes(hexsize)
        # work out the dimensions of our hexs if we haven't already
        # http://www.rdwarf.com/lerickson/hex/
        if !@@hexsizes
            @@hexsizes = {
               :a => hexsize/2,
               :b => Math.sin( 60*(Math::PI/180) )*hexsize,
               :c => hexsize
            }

            # work out what that means for our sizing
            @@hexsizes[:y] = @@hexsizes[:a] + @@hexsizes[:c]
            @@hexsizes[:x] = 2*@@hexsizes[:b]
            @@hexsizes[:xodd] = 0-@@hexsizes[:b] # step back for if y is odd
         end
        @@hexsizes
    end

    # util for getting the centre position of a hex to plot
    def self.hex_pos(x, y, hexsize, xoffset, yoffset)

      hs = self.hexsizes(hexsize)
      position = {
         :x => xoffset + (hs[:x]*x) + ((y-1) * hs[:xodd]),
         :y => yoffset + (hs[:y]*y),
      }

      position
    end

    # get coords for the corners of a hex
    def self.hex_points(x, y, hexsize)

        hs = self.hexsizes(hexsize)
        [
            {:x => x, :y => y-hs[:c]},
            {:x => x+hs[:b], :y => y-hs[:a]},
            {:x => x+hs[:b], :y => y+hs[:a]},
            {:x => x, :y => y+hs[:c]},
            {:x => x-hs[:b], :y => y+hs[:a]},
            {:x => x-hs[:b], :y => y-hs[:a]}
         ]
    end

    # transform one coord with another
   def self.transform_coord(coord, transform)
      newcoord = Hash.new
      newcoord[:x] = coord[:x] + transform[:x]
      newcoord[:y] = coord[:y] + transform[:y]
      newcoord
   end

   # rotate a transformation once clockwise - probably only works for
   # vector +/- 1 from 0,0
   def self.rotate_transform(transform)

      if transform[:x] < 0 and transform[:y] < 0
         {:x => transform[:x], :y => 0}
      elsif transform[:x] < 0 and transform[:y] == 0
         {:x => 0, :y => 0 - transform[:x]}
      elsif transform[:x] == 0 and transform[:y] > 0
         {:x => transform[:y], :y => transform[:y]}
      elsif transform[:x] > 0 and transform[:y] > 0
         {:x => transform[:x], :y => 0}
      elsif transform[:x] > 0 and transform[:y] == 0
         {:x => 0, :y => 0 - transform[:x]}
      elsif transform[:x] == 0 and transform[:y] < 0
         {:x => transform[:y], :y => transform[:y]}
      else
         transform
      end

   end

   # rotate a transformation a number of steps clockwise
   def self.rotate_transform_by(transform, steps)
      (1..steps).each { | step |
         transform = self.rotate_transform(transform)
      }
      transform
   end

    # return transforms needed to move to each adjacent area
    # for hex there are no diagonals to worry about excluding
    def self.adjacent_transforms
        [
            {:x => 1, :y => 1},
            {:x => 0, :y => 1},
            {:x => -1, :y => 0},
            {:x => -1, :y => -1},
            {:x => 0, :y => -1},
            {:x => 1, :y => 0}
        ]
   end


   # calc distance between two coords using 3rd (implied) axis
   def self.distance(from, to)

      from[:z] = from[:y] - from[:x]
      to[:z] = to[:y] - to[:x]

      dx = (from[:x] - to[:x]).abs
      dy = (from[:y] - to[:y]).abs
      dz = (from[:z] - to[:z]).abs

      [dx, dy, dz].max
   end

   # check if a coord should be included
   def self.mapcontains(size, coord)
      halfsize = (size/2).round
      middlehex = {:x => halfsize, :y => halfsize}
      self.distance(coord, middlehex) <= halfsize
   end

   # iterate coords on a hexagon map
   def self.mapcoords(size)

      coords = Array.new
      halfsize = (size/2).round
      middlehex = {:x => halfsize, :y => halfsize}

      (0..size).each { | x |
         (0..size).each { | y |
            coord = {:x => x, :y => y}
            if self.distance(coord, middlehex) <= halfsize
               coords.push coord
               yield x, y if block_given?
            end
         }
      }
      coords
   end

   def self.same_coord?(a, b)
      a[:x] == b[:x] and a[:y] == b[:y]
   end

   def self.same_line?(a, b)
      (same_coord?(a[0], b[0]) and same_coord?(a[1], b[1])) or
      (same_coord?(a[0], b[1]) and same_coord?(a[1], b[0]))
   end

   # keep transforming coord until terrain type found and return
   # the distance
   def self.find_terrain_by_transform(start, transform, terrain, size, exclude=[])

      # move one coord
      nextcoord = MapUtils::transform_coord(start, transform)

      return nil if !nextcoord
      if exclude.include? "#{nextcoord[:x]},#{nextcoord[:y]}"
         return nil
      end

      # check for desired terrain
      return nil if !MapUtils::mapcontains(size, {x: nextcoord[:x], y: nextcoord[:y]})

      if @map["#{nextcoord[:x]},#{nextcoord[:y]}"][:terrain] == terrain
         return 1
      else
         rest_of_search = MapUtils.find_terrain_by_transform(nextcoord, transform, terrain, size)
         if rest_of_search == nil
            return nil
         else
            return 1+rest_of_search
         end
      end

   end

   def self.get_hexes_in_range(state, startcoord, size, max_distance, exclude_ocean, terrain_weights)

      hexes = []
      checked = []

      MapUtils::breadth_search(startcoord, size,
         # can_be_traversed
         Proc.new { |coord, path, startnode|
            # Get terrain of current hex
            terrain = state.getHexFromCoord(coord)[:terrain]
            
            # Skip if it's ocean and we're excluding ocean
            return false if exclude_ocean && terrain == :ocean
            
            # Calculate total path cost including current hex
            path_cost = path.reduce(0) { |sum, hex| 
               sum + (terrain_weights[state.getHexFromCoord(hex)[:terrain]] || 1)
            }
            current_cost = terrain_weights[terrain] || 1
            
            # Allow traversal if within max_distance
            (path_cost + current_cost) <= max_distance
         },
         # is_found
         Proc.new { |coord, path|
            # Add valid hex to results if not already included
            hex_key = "#{coord[:x]},#{coord[:y]}"
            if !hexes.include?(hex_key)
               hexes.push(hex_key)
            end
            # Never "found" - continue searching until max_distance reached
            false
         },
         checked
      )

      hexes      
   end

   # look at adjacent hexs until match condition met, returning the path taken to that point
   def self.breadth_search(startcoord, size, can_be_traversed, is_found, checked=Array.new)

      # add coord to the queue and then process the queue
      queue = Queue.new
      queue.push({
         :coord => startcoord,
         :path => Array.new
      })

      startnode = true
      while queue.length > 0 do

         # get coord to process
         step = queue.pop
         coord = step[:coord]
         path = step[:path]

         # check if coord is inside map and not excluded
         if MapUtils::mapcontains(size, {x: coord[:x], y: coord[:y]}) and
            !checked.include? "#{coord[:x]},#{coord[:y]}"

            # add to checked
            checked.push "#{coord[:x]},#{coord[:y]}"

            # check if this hex should be blocked
            if can_be_traversed.nil? or can_be_traversed.call(coord, path, startnode)

               startnode = false

               # check if this search complete and return path
               if is_found.call(coord, path)
                  return path.push(coord)
               else

                  # add all adjacents to the queue
                  transforms = self.adjacent_transforms
                  transforms.each { | transform |

                     # add to queue
                     nextcoord = MapUtils::transform_coord(coord, transform)
                     queue.push({
                        :coord => nextcoord,
                        :path => Array.new.replace(path).push(nextcoord)
                     })
                  }
               end # found

            end # dont traverse
         end # not in map or excluded
      end # more to process

      nil
   end

   def calculate_heuristic(hex_a, hex_b, terrain_weights)
      dx = (hex_a[:x] - hex_b[:x]).abs
      dy = (hex_a[:y] - hex_b[:y]).abs

      # terrain_weight = @terrain_weights[hex_b[:terrain]] || 1
      # (dx + dy + [dx, dy].min) * terrain_weight

      dx + dy + [dx, dy].min
   end

   def reconstruct_path(came_from, current)
      path = [current]
      while came_from.key?(current)
        current = came_from[current]
        path.unshift(current)
      end
      path
   end

   # when we are searching for a path to a know coord then we can do better
   # with A* which estimates min distance and prioritises direct route
   def find_path(startcoord, endcoord, state, terrain_weights)

      start = state.getHex(startcoord[:x], startcoord[:y])
      end_hex = state.getHex(endcoord[:x], endcoord[:y])

      return nil unless start && end_hex

      open_set = [start]
      came_from = {}
      g_score = {}
      f_score = {}

      g_score[start] = 0
      f_score[start] = calculate_heuristic(start, end_hex, terrain_weights)

      while open_set.any?
        current = open_set.min_by { |hex| f_score[hex] }
        open_set.delete(current)

        return reconstruct_path(came_from, current) if current == end_hex

        neighbors = get_neighbors(current)
        neighbors.each do |neighbor|
          tentative_g_score = g_score[current] + 1
          if tentative_g_score < (g_score[neighbor] || Float::INFINITY)
            came_from[neighbor] = current
            g_score[neighbor] = tentative_g_score
            f_score[neighbor] = tentative_g_score + calculate_heuristic(neighbor, end_hex)

            open_set << neighbor unless open_set.include?(neighbor)
          end
        end
      end

      nil # No path found
    end

    def get_neighbors()
      neighbors = Array.new
      transforms = self.adjacent_transforms
      transforms.each { | transform |

         # add to queue
         nextcoord = MapUtils::transform_coord(coord, transform)
         hex = getHex(nextcoord) # cant use this here - make sure the new find_path code uses coords and not hexs for score
         neighbors.push hex
      }
   end

end

end