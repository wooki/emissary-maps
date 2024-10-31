module Emissary

require 'optparse'
require 'emissary-names'
require_relative 'map_utils.rb'

#
# Class for creating a random map
#
   class Maps

      attr_accessor :seed

      def initialize(seed=nil)

         @fng_fantasy = Emissary::Names.for_culture('fantasy')
         @fng_arid = Emissary::Names.for_culture('arid')

         @seed = seed
         @seed = Random.new_seed if !@seed
         @random = srand @seed

         # some variables for generation, usually # per size
         @mountain_ranges = 0.2
         @mountain_chance = 150
         @peak_chance = 40
         @lowland_chance = 350
         @rivers = 0.35
         @river_bend = 50
         @deserts = 0.1
         @deserts_chance = 4000
         @deserts_region = 0.2
         @deserts_region_offset = 0.4
         @forests = 18
         @forests_chance = 50
         @extra_lowland = @forests*2
         @extra_lowland_region = 0.15
         @extra_lowland_chance = 35
         @ocean_edge = 0.15
         @ocean_middle = 0.25
         @city_min_distance = 8
         @city_max_distance = 16
         @town_min_distance = 3
         @town_max_distance = 6
         @edge_ocean_chances = [100, 80, 50, 20]
         @city_away_from_edge = 10
         @town_away_from_edge = 3
         @trade_node_min_size = 13
         @trade_node_sample_size = 15
         @trade_node_land_multiplier = 3

         @population_nop_settlement = 0.1
         @population = {
            'city' => 30000,
            'town' => 10000,
            'lowland' => 1000,
            'forest' => 500,
            'mountain' => 500,
            'desert' => 250
         }
         @food = {
            'city' => 0,
            'town' => 0,
            'lowland' => 0.002,
            'forest' => 0.0015,
            'mountain' => 0.0007,
            'desert' => 0.0002
         }
         @goods = {
            'city' => 0,
            'town' => 0,
            'lowland' => 0.001,
            'forest' => 0.003,
            'mountain' => 0.002,
            'desert' => 0.001
         }
         @population_settlement_boost = [4.0, 3.0, 2.0, 1.0, 1.0, 0.75, 0.5, 0.25, 0.2, 0.15];
         @land_travel = {
            'city' => -5,
            'town' => -5,
            'lowland' => -10,
            'forest' => -20,
            'mountain' => -30,
            'desert' => -25,
            'ocean' => -1,
            'peak' => -200,
            'embark' => -180,
            'disembark' => -200,
         }
         
         # store the map as we build it
         @map = Hash.new

      end

      # actual generate a map
      def generate(size)

         # remember size
         @size = size

         # adjust generation parameters by area assuming these
         # are for 100X100 map
         area = @size*size
         areafactor = area.to_f / (100*100).to_f
         areafactor = 0.5 if areafactor < 0.5 # hardcoded minimum to ensure we get items on small maps

         @mountain_ranges = @mountain_ranges * areafactor
         @rivers = @rivers * areafactor
         @deserts = @deserts * areafactor
         @forests = @forests * areafactor
         @extra_lowland = @extra_lowland * areafactor
         @trade_node_min_size = @trade_node_min_size * areafactor
         @trade_node_sample_size = 20 - (@trade_node_sample_size * areafactor).round
         @trade_node_sample_size = 1 if @trade_node_sample_size < 1

         # adjust for a more land-based map
         # @mountain_chance = 300
         # @lowland_chance = 900

         # adjust for a more island based map
         # @mountain_ranges = 0.3
         # @mountain_chance = 70
         # @lowland_chance = 150

         # start by creating a ocean world
         Emissary::MapUtils::mapcoords(size) { | x, y |
            @map["#{x},#{y}"] = {
               x: x,
               y: y,
               terrain: 'ocean'
            }
         }

         # raise several mountains and enlarge them outwards
         mountain_ranges_to_gen = (@mountain_ranges * size).round
         (1..mountain_ranges_to_gen).each { | x |

            # get a coord within range of the center
            allowed_distance_edge = (size/2).round - ((size/2).round * @ocean_edge)
            allowed_distance_middle = ((size/2).round * @ocean_middle)
            summit = nil
            while summit == nil
               summit = Emissary::MapUtils::randcoord(size)
               if allowed_distance_edge < Emissary::MapUtils::distance(summit, {:x => (size/2).round, :y => (size/2).round})
                  summit = nil
               elsif allowed_distance_middle > Emissary::MapUtils::distance(summit, {:x => (size/2).round, :y => (size/2).round})
                  summit = nil
               end
            end

            # make summit a mountain and then each adjacent area
            # recursively has a chance
            @map["#{summit[:x]},#{summit[:y]}"][:terrain] = 'mountain'
            coords = Emissary::MapUtils::adjacent(summit, size)
            coords.each { | coord |
               make_terrain(coord, size, ['ocean'], 'mountain', @mountain_chance)
            }
         }

         # make mountains peaks if they are completely surrounded by mountains and 0-1 other peak
         mountains = get_terrain('mountain')
         mountains.each { | mountain |
            if can_be_peak(mountain, size)
               if rand(0..100) <= @peak_chance
                  mountain[:terrain] = 'peak'
               end
            end
         }

         # raise lowland around the mountain ranges
         mountains = get_terrain('mountain')
         mountains.each { | mountain |
            coords = Emissary::MapUtils::adjacent(mountain, size)
            coords.each { | coord |
               make_terrain(coord, size, ['ocean'], 'lowland', @lowland_chance)
            }
         }

         # before creating rivers turn any single area of ocean into forest
         oceans = get_terrain('ocean')
         oceans.each { | ocean |
            has_ocean_adjacent = false
            coords = Emissary::MapUtils::adjacent(ocean, size)
            coords.each { | coord |
               has_ocean_adjacent = has_ocean_adjacent || @map["#{coord[:x]},#{coord[:y]}"][:terrain] == 'ocean'
            }
            if !has_ocean_adjacent
               @map["#{ocean[:x]},#{ocean[:y]}"][:terrain] = 'forest'
            end
         }

         # raise forests randomly around
         forests_to_gen = (@forests * size).round
         forests = get_terrain('lowland').sample(forests_to_gen)
         forests.each { | forest |
            make_terrain(forest, size, ['lowland'], 'forest', @forests_chance)
         }

         # randomly add an area of desert
         deserts_to_gen = (@deserts * size).round
         from_y = ((size/2) - (size*@deserts_region)).round + (@deserts_region_offset*@size)
         to_y = ((size/2) + (size*@deserts_region)).round + (@deserts_region_offset*@size)

         deserts = get_terrain_in_region(['lowland', 'forest'], {:from => {:x => 0, :y => from_y}, :to => {:x => size, :y => to_y}}).sample(deserts_to_gen)
         deserts.each { | desert |
            make_terrain(desert, size, ['lowland', 'forest'], 'desert', @deserts_chance)
         }


         # randomly add an area of lowland within middle region to reduce forests
         extra_lowland_to_gen = (@extra_lowland * size).round
         from_y = ((size/2) - (size*@extra_lowland_region)).round
         to_y = ((size/2) + (size*@extra_lowland_region)).round

         extra_lowland = get_terrain_in_region(['forest'], {:from => {:x => 0, :y => from_y}, :to => {:x => size, :y => to_y}}).sample(extra_lowland_to_gen)
         extra_lowland.each { | extra_plain |
            make_terrain(extra_plain, size, ['lowland', 'forest'], 'lowland', @extra_lowland_chance)
         }

         # make edges ocean
         @edge_ocean_chances.each_index { | edge_ocean_chance_index |
            @map.each { | key, hex |
               if hex[:x] <= 0 or hex[:x] >= size or
                  hex[:y] <= 0 or hex[:y] >= size or
                  Emissary::MapUtils::distance(hex, {:x => (size/2).round, :y => (size/2).round}) > (size/2).round-(edge_ocean_chance_index+1)

                  if rand(0..100) <= @edge_ocean_chances[edge_ocean_chance_index]
                     hex[:terrain] = 'ocean'
                  end
               end
            }
         }

         # create rivers from mountains to the sea
         rivers_to_gen = (@rivers * size).round
         @existing_rivers = Array.new
         river_sources = get_terrain(['mountain', 'peak']).filter { | hex |
            adj = count_terrain(Emissary::MapUtils::adjacent(hex, size))
            adj['ocean'] == 0
         }.sample(rivers_to_gen)

         river_sources.each { | river |

            # find the closest edge and move in that direction 70% of the time
            # but go sideways 30% - until you reach ocean!
            # river_direction = closest_terrain_direction(river, 'ocean', size)
            river_direction = closest_ocean_direction(river, size)
            make_river(river, size, river_direction)

         }

         # create cities on areas are suitable and
         # the required distance from any other city
         allowed_settlement_terrain = get_terrain(['lowland', 'forest', 'mountain', 'desert']).shuffle
         settlements = Array.new
         allowed_settlement_terrain.each { | plain |
            if can_be_city(plain, size, settlements)
               plain[:terrain] = 'city'
               plain[:required_distance] = rand(@city_min_distance..@city_max_distance)
               settlements.push plain
            end
         }

         # adjust all cities to allow closer towns
         settlements.map! { | v |
            v[:required_distance] = rand(@town_min_distance..@town_max_distance)
            v
         }

         # create towns
         allowed_settlement_terrain.each { | plain |
            if can_be_town(plain, size, settlements)
               plain[:terrain] = 'town'
               plain[:required_distance] = rand(@town_min_distance..@town_max_distance)
               settlements.push plain
            end
         }

         # name settlements
         all_names = Hash.new
         settlements.each { | settlement |

            path = find_closest_terrain(settlement, 'desert', size)
            distance = path.length
            n = nil

            while n == nil do
               if distance < 3
                  n = @fng_arid.get_name
               else
                  n = @fng_fantasy.get_name
               end

               n = nil if all_names.has_key? n
            end

            settlement[:name] = n
         }

         # create trade nodes in large bodies of water
         trade_nodes = possible_trade_nodes(size)

         # turn into just coords
         trade_nodes.map! { | hex |
            {:x => hex[:x], :y => hex[:y]}
         }

         # add trade node to map and find closest town/city for name
         trade_nodes.each { | hex |
            hex = getHex(hex[:x], hex[:y])

            settlement_found = lambda do | coord, path |
               mapcoord = getHex(coord[:x], coord[:y])
               ["city", "town"].include? mapcoord[:terrain] and mapcoord[:trade].nil?
            end

            can_be_traversed = lambda do | coord, path, is_first |
               mapcoord = getHex(coord[:x], coord[:y])
               ["city", "town", "ocean"].include? mapcoord[:terrain]
            end

            # we won't have a path because we aren't going anywhere specific
            path_to_closest = Emissary::MapUtils::breadth_search({:x => hex[:x], :y => hex[:y]}, size, can_be_traversed, settlement_found)
            if path_to_closest
               closest = getHex(path_to_closest.last[:x], path_to_closest.last[:y])
               hex[:trade] = {
                  :name => "#{closest[:name]} Trade Node",
                  :is_node => true
               }
            else
               # need some info to diagnose why this sometimes happens
               raise "Could not find closest settlement to trade node: #{hex}"
            end
         }

         # assign each town/city to closest trade node via ocean
         get_terrain(['city', 'town']).each { | hex |

            tradenode = nil

            tradenode_found = lambda do | coord, path |
               if is_trade_node?(coord)
                  tradenode = getHex(coord[:x], coord[:y])
               else
                  false
               end
            end

            can_be_traversed = lambda do | coord, path, is_first |
               mapcoord = getHex(coord[:x], coord[:y])
               if is_first
                  ["city", "town", "ocean"].include? mapcoord[:terrain]
               else
                  ["ocean"].include? mapcoord[:terrain]
               end
            end

            path_to_closest = Emissary::MapUtils::breadth_search({:x => hex[:x], :y => hex[:y]}, size, can_be_traversed, tradenode_found)
            if path_to_closest
               hex[:trade] = {
                  :x => tradenode[:x],
                  :y => tradenode[:y],
                  :name => tradenode[:trade][:name],
                  :distance => path_to_closest.length
               }
            end
         }

         # assign each town/city that isn't attached via ocean to the closest attached
         get_terrain(['city', 'town']).each { | hex |

            if hex[:trade].nil?

               tradenode = nil

               tradenode_found = lambda do | coord, path |
                  if is_trade_node?(coord)
                     tradenode = getHex(coord[:x], coord[:y])
                  else
                     false
                  end
               end

               can_be_traversed = lambda do | coord, path, is_first |
                  mapcoord = getHex(coord[:x], coord[:y])
                  !(["peak", "mountain"].include? mapcoord[:terrain])
               end

               path_to_closest = Emissary::MapUtils::breadth_search({:x => hex[:x], :y => hex[:y]}, size, can_be_traversed, tradenode_found)
               if path_to_closest
                  hex[:trade] = {
                     :x => tradenode[:x],
                     :y => tradenode[:y],
                     :name => tradenode[:trade][:name],
                     :distance => path_to_closest.length * @trade_node_land_multiplier
                  }
               end
            end
         }

         # assign each ocean and peak to the closest tradenode
         get_terrain(['ocean']).each { | hex |

            if !is_trade_node?({:x => hex[:x], :y => hex[:y]})
               tradenode = nil

               tradenode_found = lambda do | coord, path |
                  if is_trade_node?(coord)
                     tradenode = getHex(coord[:x], coord[:y])
                  else
                     false
                  end
               end

               can_be_traversed = lambda do | coord, path, is_first |
                  mapcoord = getHex(coord[:x], coord[:y])
                  ["ocean"].include? mapcoord[:terrain]
               end

               can_be_traversed_extended = lambda do | coord, path, is_first |
                  true
               end

               path_to_closest = Emissary::MapUtils::breadth_search({:x => hex[:x], :y => hex[:y]}, size, can_be_traversed, tradenode_found)
               if path_to_closest
                  hex[:trade] = {
                     :x => tradenode[:x],
                     :y => tradenode[:y],
                     :name => tradenode[:trade][:name],
                     :distance => path_to_closest.length
                  }
               else
                  # find closest with any path
                  path_to_closest = Emissary::MapUtils::breadth_search({:x => hex[:x], :y => hex[:y]}, size, can_be_traversed_extended, tradenode_found)
                  if path_to_closest
                     hex[:trade] = {
                        :x => tradenode[:x],
                        :y => tradenode[:y],
                        :name => tradenode[:trade][:name],
                        :distance => path_to_closest.length
                     }
                  end
               end
            end
         }

         # util for checking if node exists etc
         def connect_trade_node(addto_node, this_node, vector, path)

            addto_node[:trade][:connected] = Hash.new if !addto_node[:trade][:connected]

            key = "#{this_node[:x]},#{this_node[:y]}"

            if addto_node[:trade][:connected].has_key? key
               connection = addto_node[:trade][:connected][key]
            else
               connection = {
                  :name => this_node[:trade][:name],
                  :x => this_node[:x],
                  :y => this_node[:y],
                  :distance => path.length
               }
            end

            # if !connection.has_key? :vectors
            #    connection[:vectors] = Array.new
            # end

            # connection[:vectors].push({:x => vector[:x], :y => vector[:y]})

            addto_node[:trade][:connected][key] = connection
         end

         # connect every trade node to closest three it connects to via ocean
         # @debug_hexes = Array.new
         index = 0
         trade_nodes.each { | hex |

            index = index + 1
            hex = getHex(hex[:x], hex[:y])

            closest = Hash.new
            path_to_closest = Hash.new

            tradenode_found = lambda do | coord, path |
               mapcoord = getHex(coord[:x], coord[:y])

               if is_trade_node?(coord) and mapcoord != hex

                  key = "#{mapcoord[:x]},#{mapcoord[:y]}"
                  if !closest.has_key?(key)

                     closest[key] = mapcoord
                     path_to_closest[key] = path

                     connect_trade_node(mapcoord, hex, ({:x => path[-2][:x], :y => path[-2][:y]}), path)
                     connect_trade_node(hex, mapcoord, ({:x => path[0][:x], :y => path[0][:y]}), path.reverse )
                  end
               end

               closest.keys.length >= 3
            end

            can_be_traversed = lambda do | coord, path, is_first |
               # @debug_hexes.push coord if index == 4
               return false if path.length > @size * 0.8
               mapcoord = getHex(coord[:x], coord[:y])
               ["city", "town", "ocean"].include? mapcoord[:terrain]
            end

            Emissary::MapUtils::breadth_search({:x => hex[:x], :y => hex[:y]}, size, can_be_traversed, tradenode_found)
         }

         # get actual hex listfor trade nodes
         trade_nodes = trade_nodes.map { | hex |
            getHex(hex[:x], hex[:y])
         }

         # rivers would be great for map making but not so practival for game making
         # maybe leave for now!

         # systematically find rivers (ocean with exactly two adjacent oceans that are not adjacent themselves)
         # convert to river and follow in both directions converting to river until the rule breaks - a river
         # with a coastline and one adjacent river becomes a river mouth (river terrain but graphically different)
         # TODO - on hold

         # find lakes - ocean surrounded by non-ocean. may have adjacent rivers.
         # TODO

         # find islands - non-ocean surrounded by ocean
         # TODO

         # find all ocean and set coast edges of adjacent not ocean
         # TODO

         # Trade nodes need to allow river travel if the above is added


         # set population and production
         # population = 30k for city, 10k for town
         # adjacent terrain gives bonus
         # other terrain all have a base level
         # adjacent to city/town, 2 away from city/town
         # production of each boosted by adjacent terrain
         @map.each { | key, hex |

            base_population = @population[hex[:terrain]]
            base_food = @food[hex[:terrain]]
            base_goods = @goods[hex[:terrain]]
            
               # always adjusted a bit for randomness
               base_population = 0 if base_population.nil?
               base_population = base_population + ((base_population.to_f / 100.0) * rand() * rand(-15..15).to_f).round.to_i

               if ['city', 'town'].include? hex[:terrain]

                  # adjusted by adjacent hexes only
                  adj = count_terrain(Emissary::MapUtils::adjacent({:x => hex[:x], :y => hex[:y]}, size))
                  adjustment = 1.0

                  adjustment = adjustment + (adj['desert'].to_f * 0.1) if adj['desert'] > 0
                  adjustment = adjustment + (adj['ocean'].to_f * 0.05) if adj['ocean'] > 0

                  base_population = (base_population.to_f * adjustment).round.to_i
                  hex[:population] = base_population
                  

               else

                  # adjusted by adjacent oceans
                  adj = count_terrain(Emissary::MapUtils::adjacent({:x => hex[:x], :y => hex[:y]}, size))
                  adjustment = 1.0
                  adjustment = adjustment + (adj['ocean'].to_f * 0.05) if adj['ocean'] > 0

                  # route with weighted distance
                  weighted_distance = lambda do | coord, path |
                     mapcoord = getHex(coord[:x], coord[:y])
                     return 0 if !mapcoord                                       
                     return @land_travel[mapcoord[:terrain]] if path.length == 0

                     previous = getHex(path.last[:x], path.last[:y])
                     if previous[:terrain] == 'ocean' && mapcoord[:terrain] != 'ocean' 
                        return @land_travel[mapcoord[:terrain]] + @land_travel['disembark']
                     elsif !['city', 'town', 'ocean'].include?(previous[:terrain]) && mapcoord[:terrain] == 'ocean' 
                        return @land_travel[mapcoord[:terrain]] + @land_travel['embark']
                     end                    

                     @land_travel[mapcoord[:terrain]]
                  end

                  # adjusted by distance to closest town/city
                  path = find_closest_terrain({:x => hex[:x], :y => hex[:y]}, ['town', 'city'], size, exclude=[], weight=weighted_distance)
                  if !path.nil?

                     if path.length > (@population_settlement_boost.length - 1)
                        adjustment = adjustment * @population_nop_settlement
                     else
                        adjustment = adjustment * @population_settlement_boost[path.length]
                     end

                     # also remember the settlement to which this area is attached
                     province = getHex path.last[:x], path.last[:y]
                     hex[:province] = {
                        :name => province[:name],
                        :x => path.last[:x],
                        :y => path.last[:y],
                        :distance => path.length
                     }

                     # settlement also stores reference to coords that it owns
                     province[:areas] = Array.new if !province[:areas]
                     province[:areas].push({:x => hex[:x], :y => hex[:y]})
                  end
                  # no path to a settlement - isolated islands stay x1

                  base_population = (base_population.to_f * adjustment).round.to_i
                  hex[:population] = base_population

                  # extra food in lowland adjacent to desert and water
                  if hex[:terrain] == 'lowland' and adj['desert'] > 0 and adj['ocean'] > 0
                     base_food = base_food + (adj['desert'].to_f * 0.0003)
                  end

                  hex[:food] = base_food
                  hex[:goods] = base_goods
               end
            # end
         }

         # check if we can reach the province capital from every hex
         @map.each { | key, hex |

            if !['city', 'town'].include? hex[:terrain]

               other_province = nil

               # have we arrived at the capital
               is_found = lambda do | coord, path |
                  coord[:x] == hex[:province][:x] and coord[:y] == hex[:province][:y]                                    
               end

               # only traverse if we are in the same province
               can_be_traversed = lambda do | coord, path, is_first |

                  return true if is_found.call(coord, path)
                  mapcoord = @map["#{coord[:x]},#{coord[:y]}"]
                  return false if hex[:terrain] == 'ocean' and mapcoord[:terrain] != 'ocean'
                  return false if ['city', 'town'].include? mapcoord[:terrain]
                  
                  same_province = mapcoord[:province][:x] == hex[:province][:x] and mapcoord[:province][:y] == hex[:province][:y]
                  other_province = mapcoord[:province] if !same_province && !other_province
                  same_province
               end

               path = Emissary::MapUtils::breadth_search({:x => hex[:x], :y => hex[:y]}, size, can_be_traversed, is_found)
               
               hex[:province] = other_province if path.nil? if other_province                                            
            end
         }

         # try again for debugging (do twice because first run might cause the issue)     
         1.times {
            @map.each { | key, hex |

               if !['city', 'town'].include? hex[:terrain]

                  other_province = nil

                  debug = false
                  debug = true if hex[:x] == 42 and hex[:y] == 52
                  
                  # have we arrived at the capital
                  is_found = lambda do | coord, path |
                     coord[:x] == hex[:province][:x] and coord[:y] == hex[:province][:y]                                    
                  end

                  # only traverse if we are in the same province
                  can_be_traversed = lambda do | coord, path, is_first |

                     return true if is_found.call(coord, path)
                     mapcoord = @map["#{coord[:x]},#{coord[:y]}"]
                     return false if ['city', 'town'].include? mapcoord[:terrain]
                     
                     
                     same_province = (mapcoord[:province][:x] == hex[:province][:x]) && (mapcoord[:province][:y] == hex[:province][:y])
                     
                     other_province = mapcoord[:province] if !same_province && !other_province
                     same_province
                  end

                  path = Emissary::MapUtils::breadth_search({:x => hex[:x], :y => hex[:y]}, size, can_be_traversed, is_found)

                  # hex[:province] = other_province if path.nil?                                                 
                  @map[key][:province] = other_province if path.nil?
               end
            }
         }
               

         # work out border areas and adjacent provinces
         @map.each { | key, hex |
            if ['city', 'town'].include? hex[:terrain]

               # work out all border areas of a province and which provinces
               # are it's neighbours
               neighbours = Array.new
               borders = Array.new
               hex[:areas].each { | area |                                 
                  # check if adjacent areas are in a different province
                  adjacent = Emissary::MapUtils::adjacent({:x => area[:x], :y => area[:y]}, size)
                  adjacent.each { | adjacent_area |
                     adjacent_hex = getHex(adjacent_area[:x], adjacent_area[:y]);
                     if !['city', 'town'].include? adjacent_hex[:terrain]
                        if adjacent_hex[:province][:x] != hex[:x] or adjacent_hex[:province][:y] != hex[:y]
                           borders.push({x: area[:x], y: area[:y]})
                           neighbours.push({x: adjacent_hex[:province][:x], y: adjacent_hex[:province][:y]})
                        end
                     end
                  }
               }

               hex[:neighbours] = neighbours.uniq
               hex[:borders] = borders.uniq               
            end
         }

         # itrare each province and log coast
         @map.each { | key, hex |
            if ['city', 'town'].include? hex[:terrain]

               coast = Array.new
               hex[:areas].each { | area | 
                  a = getHex area[:x], area[:y]
                  if a[:terrain] == 'ocean'
                     adjacent = Emissary::MapUtils::adjacent({:x => area[:x], :y => area[:y]}, size)
                     adjacent.each { | adjacent_area |
                        adjacent_hex = getHex(adjacent_area[:x], adjacent_area[:y]);
                        if adjacent_hex[:terrain] != 'ocean'
                           coast.push({x: area[:x], y: area[:y]}) 
                        end
                     }  
                  end
               }
               hex[:coast] = coast.uniq
            end
         }

         # rename everything now we have it all linked up.
         trade_nodes.each { | trade_node |

            # work out the namer we want for the region
            terrain_in_region = Hash.new
            @map.each { | key, hex |               
            
               hex_is_trade_node = hex[:x] == trade_node[:x] && hex[:y] == trade_node[:y]
               hex_is_province_center = trade_node[:province] && hex[:x] == trade_node[:province][:x] && hex[:y] == trade_node[:province][:y]               
               hex_is_in_trade_node = hex[:trade] && hex[:trade][:x] == trade_node[:x] && hex[:trade][:y] == trade_node[:y]

               hex_is_province_area = false
               if trade_node[:province] && hex[:province]
                  province = getHex(hex[:province][:x], hex[:province][:y])
                  hex_is_province_area = province[:trade][:x] == trade_node[:x] && province[:trade][:y] == trade_node[:y]
               end

               if hex_is_trade_node || hex_is_province_center || hex_is_province_area || hex_is_in_trade_node
                  
                  if !terrain_in_region[hex[:terrain]]
                     terrain_in_region[hex[:terrain]] = 0
                  end
                  terrain_in_region[hex[:terrain]] = terrain_in_region[hex[:terrain]] + 1                                                   
               end
            }                        
            region = Names.get_culture_for_terrain(terrain_in_region)            
            namer = Names.for_culture(region)
            trade_node[:name_region] = namer.culture
            trade_node[:namer] = namer  
            name = namer.get_name    
            trade_node[:name] = "#{name} Region"          
            
            total_terrain_count = terrain_in_region.values.sum
            trade_node[:trade][:name] = "#{name} Region"
         }
         

         
         # iterate every settlement and name based on that settlements region
         @map.each { | key, hex |
            if ['city', 'town'].include? hex[:terrain]
               trade = getTradeNode hex
               
               if trade                  
                  name = trade[:namer].get_name
                  
                  # name the node   
                  hex[:name] = name

                  # name the trade node                  
                  hex[:trade][:name] = trade[:name]

               else
                  puts "no trade node found for #{hex[:x]},#{hex[:y]}"
               end
            end
         }

         # iterate all non settlements setting province and trade node
         @map.each { | key, hex |
            if !['city', 'town'].include? hex[:terrain]

               province = getHex(hex[:province][:x], hex[:province][:y])
               hex[:province][:name] = province[:name]

               if hex[:trade] && !hex[:trade][:is_node]
                  
                  hex[:trade] = province[:trade]                      

               elsif hex[:trade]
                  
                  if hex[:trade][:connected]
                     hex[:trade][:connected].each { | key, connected |
                     
                     connected_node = getTradeNode connected
                     connected[:name] = connected_node[:name]
                     }
                  end
               end
            end
         }  
         
         # remove some side-effect keys e.g. :z and :required_distance
         @map.each { | key, hex |
            hex.delete(:z)
            hex.delete(:required_distance)
         }
         trade_nodes.each { | trade_node |
            trade_node.delete(:namer)
         }
         
         @map
      end

      def getHex(x, y)
         @map["#{x},#{y}"]
      end

      def is_trade_node?(coords)
         hex = getHex(coords[:x], coords[:y])
         hex[:trade] and hex[:trade][:is_node]
      end

      def getTradeNode(coords)
         hex = getHex(coords[:x], coords[:y])
         if hex[:trade] and hex[:trade][:is_node] 
            hex
         elsif hex[:trade] and hex[:trade][:x] and hex[:trade][:y]
            getHex hex[:trade][:x], hex[:trade][:y]
         else
            nil
         end
      end

      # finds all ocean hexs that are surrounded by ocean in all directions by at
      # least @trade_node_min_size
      def possible_trade_nodes(size)

         # only ever check a certain distance
         max_range = 2 * @trade_node_min_size

         # get all water that is completely surrounded by water
         # then reduce list as much as possible for speed
         possible_nodes = get_terrain('ocean').filter { | hex |
            adj = count_terrain(Emissary::MapUtils::adjacent(hex, size))
            adj['ocean'] == 6
         }

         # any near edge will be found anyway - so safe to remove a lot
         possible_nodes.filter! { | hex |
            dist_from_middle = Emissary::MapUtils::distance(hex, {:x => (size/2).round, :y => (size/2).round})
            dist_from_middle < (size/2).round-4
         }

         # just remove 1 in X nodes in the list - will be found anyway
         possible_nodes = possible_nodes.shuffle.each_slice(@trade_node_sample_size).map(&:first)

         # find all possible trade nodes (blocks of ocean)
         possible_nodes = possible_nodes.map { | hex |
            possible_trade_node(hex, size, max_range)
         }
         possible_nodes.compact!

         # order by number of times that center hex appears and then by size
         possible_nodes.sort! { | a, b |
            count_a = possible_nodes.filter { | x | x[:x] == a[:x] and x[:y] == a[:y] }.length
            count_b = possible_nodes.filter { | x | x[:x] == b[:x] and x[:y] == b[:y] }.length
            if count_a == count_b
               a[:hexes].length <=> b[:hexes].length
            else
               count_a <=> count_b
            end
         }
         possible_nodes.reverse!

         # remove any subsequent nodes that appear in an earlier block
         possible_nodes.filter! { | node |
            found = false

            node_index = possible_nodes.index { | n | n[:x] == node[:x] and n[:y] == node[:y] }

            better_nodes = possible_nodes.slice(node_index + 1, possible_nodes.length)

            if better_nodes.length > 0
               better_nodes.each { | better_node |

                  if better_node[:x] == node[:x] and better_node[:y] == node[:y]
                     found = true
                  elsif better_node[:hexes].index { | n | n[:x] == node[:x] and n[:y] == node[:y] }
                     found = true
                  end
               }
            end

            !found
         }
      end

      # find the ocean area around a hex and check if center is ocean
      def possible_trade_node(start, size, max_range)

         # search continues up to a reasonable max
         is_found = lambda do | coord, path |
            false # never found in this use
         end

         # remember all hexs
         searched_hexes = Array.new
         can_be_traversed = lambda do | coord, path, is_first |
            # exclude once we hit a max range from start
            distance = Emissary::MapUtils::distance(coord, {:x => start[:x], :y => start[:y]})
            return false if distance > max_range

            # check terrain
            mapcoord = @map["#{coord[:x]},#{coord[:y]}"]
            can_traverse = mapcoord[:terrain] == 'ocean'
            searched_hexes.push(mapcoord) if can_traverse

            can_traverse
         end

         # we won't have a parh because we aren't going anywhere specific
         Emissary::MapUtils::breadth_search({:x => start[:x], :y => start[:y]}, size, can_be_traversed, is_found)

         # check center
         max_x = searched_hexes.reduce(0) do | sum, hex |
            sum + hex[:x]
         end
         max_y = searched_hexes.reduce(0) do | sum, hex |
            sum + hex[:y]
         end
         center_x = (max_x.to_f / searched_hexes.length.to_f).round
         center_y = (max_y.to_f / searched_hexes.length.to_f).round

         # not allowed if not ocean and surrounded by ocean
         center_hex = getHex(center_x, center_y)
         return nil if center_hex[:terrain] != 'ocean'
         adj = count_terrain(Emissary::MapUtils::adjacent(center_hex, size))
         return nil if adj['ocean'] != 6

         # return center point and hexes that it contains
         return {
            :x => center_x,
            :y => center_y,
            :hexes => searched_hexes
         };

      end

      # check if this area is suitable for a town
      # 1+ ocean and 2+ lowland/forest
      def can_be_town(coord, size, existing_settlements)

         # check adjacent terrain
         adj = count_terrain(Emissary::MapUtils::adjacent(coord, size))
         if (adj['desert'] >= 3 and
            adj['ocean'] >= 1) or
            (adj['ocean'] >= 1 and
            adj['lowland'] >= 1 and
            adj['lowland']+adj['forest'] >= 3)

            # check if too close to edge
            if Emissary::MapUtils::distance(coord, {:x => (size/2).round, :y => (size/2).round}) >= (size/2).round-@town_away_from_edge
               return false
            end

            # check existing villages not too close
            existing_settlements.each { | village |
               if (village[:x] - coord[:x]).abs <= village[:required_distance] and
                  (village[:y] - coord[:y]).abs <= village[:required_distance]
                  return false
               end
            }
            true
         else
            false
         end
      end

      # check if this area is suitable for a city
      # 1+ ocean and 2+ lowland/forest
      def can_be_city(coord, size, existing_settlements)

         # check adjacent terrain
         adj = count_terrain(Emissary::MapUtils::adjacent(coord, size))
         if (adj['desert'] >= 3 and
            adj['ocean'] >= 1) or
            (adj['ocean'] >= 1 and
            adj['lowland'] >= 1 and
            adj['forest'] >= 1 and
            adj['lowland']+adj['forest'] >= 3)

            # check if too close to edge
            if Emissary::MapUtils::distance(coord, {:x => (size/2).round, :y => (size/2).round}) >= (size/2).round-@city_away_from_edge
               return false
            end

            # check existing villages not too close
            existing_settlements.each { | village |
               if (village[:x] - coord[:x]).abs <= village[:required_distance] and
                  (village[:y] - coord[:y]).abs <= village[:required_distance]
                  return false
               end
            }
            true
         else
            false
         end
      end

      # check if this area is suitable for a peak
      # all mountain, optionally 1 peak adjacent
      def can_be_peak(coord, size)

         # check adjacent terrain
         adj = count_terrain(Emissary::MapUtils::adjacent(coord, size))
         if adj['mountain'] == 6 or
            (adj['mountain'] == 5 and
            adj['peak'] == 1)

            true
         else
            false
         end
      end

      # util for counting terrain types
      def count_terrain(coords)

         total = {'ocean' => 0, 'town' => 0, 'lowland' => 0,
                  'mountain' => 0, 'forest' => 0, 'desert' => 0,
                  'peak' => 0, 'city' => 0, 'river' => 0 }

         coords.each { | coord |
            mapcoord = @map["#{coord[:x]},#{coord[:y]}"]
            total[mapcoord[:terrain]] += 1
         }

         total
      end

      # try and make this area a mountain and then check any
      # adjacent area
      def make_terrain(coord, size, from_terrains, to_terrain, chance)

         if from_terrains.include? @map["#{coord[:x]},#{coord[:y]}"][:terrain]
            if rand(0..100) <= chance
               @map["#{coord[:x]},#{coord[:y]}"][:terrain] = to_terrain
               coords = Emissary::MapUtils::adjacent(coord, size)
               coords.each { | coord |
                  make_terrain(coord, size, from_terrains, to_terrain, chance*0.75)
               }
            end
         end

      end

      # make this area a river and then move in transform direction (or bend sometimes)
      def make_river(coord, size, transform, ocean_count=0)

         map_area = @map["#{coord[:x]},#{coord[:y]}"]
         return if !map_area

         # handle meeting ocean is tricky. If we hit another river then stop.
         # If we hit 2+ ocean in a row stop otherwise carry one.
         if map_area[:terrain] == 'ocean'
            return false if @existing_rivers.include? "#{coord[:x]},#{coord[:y]}"
            ocean_count += 1
            return true if ocean_count > 1
         else
            ocean_count = 0
         end

         result = true
         if rand(0..100) <= @river_bend
            if rand(0..100) <= 49
               next_coord = Emissary::MapUtils::transform_coord(coord, Emissary::MapUtils::rotate_transform(transform))
            else
               next_coord = Emissary::MapUtils::transform_coord(coord, Emissary::MapUtils::rotate_transform_by(transform, 5))
            end
         else
            next_coord = Emissary::MapUtils::transform_coord(coord, transform)
         end

         make_river(next_coord, size, transform, ocean_count)

         if result
            map_area[:terrain] = 'ocean'
            @existing_rivers = Array.new if !@existing_rivers
            @existing_rivers.push "#{coord[:x]},#{coord[:y]}"
         end
         result
      end

      # get all terrain of one type
      def get_terrain(terrain)
         if !terrain.kind_of? Array
            terrain = [terrain]
         end

         coords = Array.new
         @map.each { | key, value |
            if terrain.include? value[:terrain]
               coords.push(value)
            end
         }
         coords
      end


      # get all terrain of one type from within a region
      def get_terrain_in_region(terrain, region)
         coords = Array.new
         @map.each { | key, hex |
            if hex[:x] >= region[:from][:x] and
               hex[:x] <= region[:to][:x] and
               hex[:y] >= region[:from][:y] and
               hex[:y] <= region[:to][:y]

               if !terrain.kind_of? Array
                  terrain = [terrain]
               end
               if terrain.include? hex[:terrain]
                  coords.push(hex)
               end
            end
         }
         coords
      end


      # find the direction of closest terrain of certain type
      # and return as a transform
      # def closest_terrain_direction(coord, terrain, size, exclude=[])

      #    path = find_closest_terrain(coord, terrain, size, exclude)

      #    # get transform of first step if there is one
      #    if path and path.length > 0

      #       first = path.first
      #       {
      #          :x => (first[:x] - coord[:x]),
      #          :y => (first[:y] - coord[:y])
      #       }

      #    else
      #       nil
      #    end
      # end

      # find the direction of closest ocean surrounded by ocean (i.e. skip rivers!)
      def closest_ocean_direction(start, size, exclude=[])

         terrain_found = lambda do | coord, path |
            mapcoord = getHex(coord[:x], coord[:y])
            if mapcoord[:terrain] == 'ocean'

               adj = count_terrain(Emissary::MapUtils::adjacent(coord, size))
               adj['ocean'] == 6

            else
               false
            end
         end

         path = Emissary::MapUtils::breadth_search({:x => start[:x], :y => start[:y]}, size, nil, terrain_found, exclude)

         # get transform of first step if there is one
         if path and path.length > 0

            first = path.first
            {
               :x => (first[:x] - start[:x]),
               :y => (first[:y] - start[:y])
            }

         else
            nil
         end
      end

      def find_closest_terrain(start, terrain, size, exclude=[], weight=nil)

         terrain = [terrain] if !terrain.kind_of?(Array)

         terrain_found = lambda do | coord, path |
            mapcoord = getHex(coord[:x], coord[:y])
            terrain.include? mapcoord[:terrain]
         end
         if weight
            return Emissary::MapUtils::weighted_breadth_search({:x => start[:x], :y => start[:y]}, size, nil, terrain_found, exclude, weight=weight)
         end

         return Emissary::MapUtils::breadth_search({:x => start[:x], :y => start[:y]}, size, nil, terrain_found, exclude)
      end

      # output as svg
      def to_svg(hexsize=100, io)

         hex_b = 2*Math.sin( 60*(Math::PI/180) )*hexsize
         xoffset = (hex_b/2).round + Emissary::MapUtils::hex_pos(0, (@size/2).round, hexsize, 0, 0)[:x].abs
         yoffset = hexsize*1.25
         canvassize_x = ((@size+1) * hex_b).round
         canvassize_y = hexsize * 1.5 * (@size + 2)

         io.print "<?xml version=\"1.0\"?>"
         io.print "<!-- SEED: \"#{@seed}\" -->"
         io.print "<svg width=\"#{canvassize_x}\" height=\"#{canvassize_y}\""
         io.print " viewPort=\"0 0 #{canvassize_x} #{canvassize_y}\" version=\"1.1\""
         io.print " xmlns=\"http://www.w3.org/2000/svg\">\n"
         io.print "<rect width=\"#{canvassize_x}\" height=\"#{canvassize_y}\" fill=\"#3D59AB\"/>"

         # create icons
         io.print "<symbol id=\"trade\" width=\"#{hexsize}\" height=\"#{hexsize}\" viewBox=\"0 0 512 512\">"
         io.print '<path xmlns="http://www.w3.org/2000/svg" d="M203.97 23l-18.032 4.844 11.656 43.468c-25.837 8.076-50.32 21.653-71.594 40.75L94.53 80.594l-13.218 13.22 31.376 31.374c-19.467 21.125-33.414 45.53-41.813 71.343l-42.313-11.343-4.843 18.063 42.25 11.313c-6.057 27.3-6.157 55.656-.345 83L23.72 308.78l4.843 18.064 41.812-11.22c6.693 21.225 17.114 41.525 31.25 59.876l-29.97 52.688-16.81 29.593 29.56-16.842 52.657-29.97c18.41 14.216 38.784 24.69 60.094 31.407l-11.22 41.844 18.033 4.81 11.218-41.905c27.345 5.808 55.698 5.686 83-.375l11.312 42.28 18.063-4.81-11.344-42.376c25.812-8.4 50.217-22.315 71.342-41.78l31.375 31.373 13.22-13.218-31.47-31.47c19.09-21.266 32.643-45.738 40.72-71.563l43.53 11.657 4.813-18.063-43.625-11.686c5.68-27.044 5.576-55.06-.344-82.063l43.97-11.78-4.813-18.063L440.908 197c-6.73-20.866-17.08-40.79-31.032-58.844l29.97-52.656 16.842-29.563-29.593 16.844-52.656 29.97c-17.998-13.875-37.874-24.198-58.657-30.906l11.783-44L309.5 23l-11.78 43.97c-27-5.925-55.02-6.05-82.064-.376L203.97 23zm201.56 85L297.25 298.313l-.75.437-40.844-40.875-148.72 148.72-2.186 1.25 109.125-191.75 41.78 41.78L405.532 108zm-149.686 10.594c21.858 0 43.717 5.166 63.594 15.47l-116.625 66.342-2.22 1.28-1.28 2.22-66.25 116.406c-26.942-52.04-18.616-117.603 25.03-161.25 26.99-26.988 62.38-40.468 97.75-40.468zm122.72 74.594c26.994 52.054 18.67 117.672-25.002 161.343-43.66 43.662-109.263 52.005-161.312 25.033l116.438-66.282 2.25-1.25 1.25-2.25 66.375-116.592z" />'
         io.print '</symbol>'

         io.print "<symbol id=\"town\" width=\"#{hexsize}\" height=\"#{hexsize}\" viewBox=\"0 0 512 512\">"
         io.print '<path xmlns="http://www.w3.org/2000/svg" d="M109.902 35.87l-71.14 59.284h142.28l-71.14-59.285zm288 32l-71.14 59.284h142.28l-71.14-59.285zM228.73 84.403l-108.9 90.75h217.8l-108.9-90.75zm-173.828 28.75v62h36.81l73.19-60.992v-1.008h-110zm23 14h16v18h-16v-18zm265 18v10.963l23 19.166v-16.13h16v18h-13.756l.104.087 19.098 15.914h-44.446v14h78v-39h18v39h14v-62h-110zm-194.345 48v20.08l24.095-20.08h-24.095zm28.158 0l105.1 87.582 27.087-22.574v-65.008H176.715zm74.683 14h35.735v34h-35.735v-34zm-76.714 7.74L30.37 335.153H319l-144.314-120.26zm198.046 13.51l-76.857 64.047 32.043 26.704H481.63l-108.9-90.75zm-23.214 108.75l.103.086 19.095 15.914h-72.248v77.467h60.435v-63.466h50v63.467h46v-93.466H349.516zm-278.614 16V476.13h126v-76.976h50v76.977h31.565V353.155H70.902zm30 30h50v50h-50v-50z" />'
         io.print '</symbol>'

         io.print "<symbol id=\"city\" width=\"#{hexsize}\" height=\"#{hexsize}\" viewBox=\"0 0 512 512\">"
         io.print '<path xmlns="http://www.w3.org/2000/svg" d="M255.95 27.11L180.6 107.614l150.7 1.168-75.35-81.674h-.003zM25 109.895v68.01l19.412 25.99h71.06l19.528-26v-68h-14v15.995h-18v-15.994H89v15.995H71v-15.994H57v15.995H39v-15.994H25zm352 0v68l19.527 26h71.06L487 177.906v-68.01h-14v15.995h-18v-15.994h-14v15.995h-18v-15.994h-14v15.995h-18v-15.994h-14zm-176 15.877V260.89h110V126.63l-110-.857zm55 20.118c8 0 16 4 16 12v32h-32v-32c0-8 8-12 16-12zM41 221.897V484.89h78V221.897H41zm352 0V484.89h78V221.897h-78zM56 241.89c4 0 8 4 8 12v32H48v-32c0-8 4-12 8-12zm400 0c4 0 8 4 8 12v32h-16v-32c0-8 4-12 8-12zm-303 37v23h-16v183h87v-55c0-24 16-36 32-36s32 12 32 36v55h87v-183h-16v-23h-14v23h-18v-23h-14v23h-18v-23h-14v23h-18v-23h-14v23h-18v-23h-14v23h-18v-23h-14v23h-18v-23h-14zm-49 43c4 0 8 4 8 12v32H96v-32c0-8 4-12 8-12zm72 0c8 0 16 4 16 12v32h-32v-32c0-8 8-12 16-12zm80 0c8 0 16 4 16 12v32h-32v-32c0-8 8-12 16-12zm80 0c8 0 16 4 16 12v32h-32v-32c0-8 8-12 16-12zm72 0c4 0 8 4 8 12v32h-16v-32c0-8 4-12 8-12zm-352 64c4 0 8 4 8 12v32H48v-32c0-8 4-12 8-12zm400 0c4 0 8 4 8 12v32h-16v-32c0-8 4-12 8-12z"/>'
         io.print '</symbol>'

         # assign each trade node a color
         colors = ['mediumvioletred', 'indigo', 'darkviolet', 'midnightblue', 'saddlebrown', 'chocolate', 'maroon', 'deeppink'].shuffle
         trade_node_colors = Hash.new
         @map.each { | key, hex |
            if is_trade_node? hex
               trade_node_colors[key] = colors.pop
            end
         }

         @map.each { | key, hex |

            terrain = hex[:terrain]
            if terrain == "peak"
               # terrain = "silver"
               terrain_color = "dimgray"
            elsif terrain == "ocean"
               if is_trade_node? hex
                  # terrain_color = hex[:tradenode]
                  # terrain_color = "blueviolet"
                  terrain_color = trade_node_colors[key]
               else
                  terrain_color = "#3D59AB"
               end
            elsif terrain == "mountain"
               terrain_color = "slategray"
            elsif terrain == "lowland"
               terrain_color = "limegreen"
            elsif terrain == "forest"
               terrain_color = "forestgreen"
            elsif terrain == "desert"
               terrain_color = "goldenrod"
            elsif terrain == "town"
               terrain_color = "black"
            elsif terrain == "city"
               terrain_color = "red"
            end

            pos = Emissary::MapUtils::hex_pos(hex[:x], hex[:y], hexsize, xoffset, yoffset)
            hexsizes = Emissary::MapUtils::hexsizes(hexsize)
            hex_points = Emissary::MapUtils::hex_points(pos[:x], pos[:y], hexsize)

            io.print "<polygon points=\""
            hex_points.each { | hex_point |
               io.print "#{hex_point[:x].round(2)},#{hex_point[:y].round(2)} "
            }
            # io.print "\" fill=\"#{terrain_color}\" stroke=\"#{terrain_color}\" />"
            # io.print "\" fill=\"#{terrain_color}\" stroke=\"black\" stroke-width=\"0.5\" />"
            stroke = "black"
            stroke_width= 0.1
            if terrain == "ocean" and !(is_trade_node?(hex) and hex[:trade])

               # stroke = trade_node_colors["#{hex[:trade][:x]},#{hex[:trade][:y]}"]
               # stroke_width = 1.0
               # terrain_color = trade_node_colors["#{hex.trade_node.x},#{hex.trade_node.y}".to_sym]

            elsif terrain != "peak" and !is_trade_node?(hex) and !hex[:trade] and hex[:province]
               # capital = getHex hex[:province][:x], hex[:province][:y]
               # if capital and capital[:trade]
               #    stroke = trade_node_colors["#{capital[:trade][:x]},#{capital[:trade][:y]}"]
               #    stroke_width = 2.0
               # end               
            end
            io.print "\" fill=\"#{terrain_color}\" stroke=\"#{stroke}\" stroke-width=\"#{stroke_width}\" />"

            x = pos[:x].to_f - (hexsize.to_f/2).to_f
            y = pos[:y].to_f - (hexsize.to_f/2).to_f
            if terrain == "town"
               io.print "<use href=\"#town\" x=\"#{x.round(2)}\"  y=\"#{y.round(2)}\" fill=\"white\" style=\"opacity:1.0\" />"
            elsif terrain == "city"
               io.print "<use href=\"#city\" x=\"#{x.round(2)}\"  y=\"#{y.round(2)}\" fill=\"white\" style=\"opacity:1.0\" />"
            elsif terrain == "ocean" and is_trade_node? hex
               io.print "<use href=\"#trade\" x=\"#{x.round(2)}\"  y=\"#{y.round(2)}\" fill=\"black\" style=\"opacity:0.8\" />"
            end

            io.print "<text font-size=\"8px\" x=\"#{x}\" y=\"#{pos[:y]}\" fill=\"white\">#{hex[:x]},#{hex[:y]}</text>"
         }

         # Draw lines from non-city/town hexes to their province capitals
         @map.each { |key, hex|
            if hex[:province] && hex[:terrain] != "city" && hex[:terrain] != "town"
               province_hex = getHex(hex[:province][:x], hex[:province][:y])
               if province_hex
                  start_pos = Emissary::MapUtils::hex_pos(hex[:x], hex[:y], hexsize, xoffset, yoffset)
                  end_pos = Emissary::MapUtils::hex_pos(province_hex[:x], province_hex[:y], hexsize, xoffset, yoffset)
                  
                  io.print "<line x1=\"#{start_pos[:x].round(2)}\" y1=\"#{start_pos[:y].round(2)}\" " +
                           "x2=\"#{end_pos[:x].round(2)}\" y2=\"#{end_pos[:y].round(2)}\" " +
                           "stroke=\"red\" stroke-width=\"0.5\" stroke-opacity=\"0.3\" />"
               end
            end
         }


         # town and city labels
         @map.each { | key, hex |

            if hex[:terrain] == "city" or hex[:terrain] == "town" or
               (hex[:terrain] == "ocean" and is_trade_node? hex)

               pos = Emissary::MapUtils::hex_pos(hex[:x], hex[:y], hexsize, xoffset, yoffset)
               hexsizes = Emissary::MapUtils::hexsizes(hexsize)
               hex_points = Emissary::MapUtils::hex_points(pos[:x], pos[:y], hexsize)

               x = hex_points[2][:x].round(2)
               y = hex_points[2][:y].round(2)
               color = "black"

               font_size = '20px'
               font_size = '14px' if hex[:terrain] == "town"

               text = hex[:name]
               text = hex[:trade][:name] if text.nil?
               io.print "<text font-size=\"#{font_size}\" x=\"#{x}\" y=\"#{y}\" fill=\"#{color}\">#{text}</text>"

            end
         }

         # draw borders
         @map.each { | key, hex |
            if hex[:terrain] == "city" or hex[:terrain] == "town"
               borders = hex[:borders]
               borders.each do |border_coord|
                  border_hex = getHex(border_coord[:x], border_coord[:y])
                  adjacent_hexes = Emissary::MapUtils::adjacent(border_hex, @size).map { |adj_hex| getHex(adj_hex[:x], adj_hex[:y]) }                  
                  different_province_hexes = adjacent_hexes.select { |adj_hex|                      
                     if adj_hex[:province]
                        adj_hex[:province][:x] != border_hex[:province][:x] or adj_hex[:province][:y] != border_hex[:province][:y]
                     else
                        adj_hex[:name] != border_hex[:province][:name]
                     end
                  }

                  border_pos = Emissary::MapUtils::hex_pos(border_hex[:x], border_hex[:y], hexsize, xoffset, yoffset)
                  border_points = Emissary::MapUtils::hex_points(border_pos[:x], border_pos[:y], hexsize)
                     
                  different_province_hexes.each do |adj_hex|                     
                     adj_pos = Emissary::MapUtils::hex_pos(adj_hex[:x], adj_hex[:y], hexsize, xoffset, yoffset)                     
                     adj_points = Emissary::MapUtils::hex_points(adj_pos[:x], adj_pos[:y], hexsize)
                     
                     shared_points = border_points.select { |bp|
                        adj_points.any? { |ap| 
                           (bp[:x] - ap[:x]).abs < 0.01 && (bp[:y] - ap[:y]).abs < 0.01
                        }
                     }

                     if shared_points.length == 2
                        io.print "<line x1=\"#{shared_points[0][:x].round(2)}\" y1=\"#{shared_points[0][:y].round(2)}\" " +
                                 "x2=\"#{shared_points[1][:x].round(2)}\" y2=\"#{shared_points[1][:y].round(2)}\" " +
                                 "stroke=\"red\" stroke-width=\"2\" />"
                     end
                  end
               end
               
            end
         }

         # debug searched path
         # if @debug_hexes

         #    @debug_hexes.uniq!

         #    @debug_hexes.each { | hex |

         #       if hex[:tradenode].nil? && hex[:trade].nil?
         #          pos = Emissary::MapUtils::hex_pos(hex[:x], hex[:y], hexsize, xoffset, yoffset)
         #          hexsizes = Emissary::MapUtils::hexsizes(hexsize)
         #          hex_points = Emissary::MapUtils::hex_points(pos[:x], pos[:y], hexsize)

         #          io.print "<polygon points=\""
         #          hex_points.each { | hex_point |
         #             io.print "#{hex_point[:x].round(2)},#{hex_point[:y].round(2)} "
         #          }
         #          io.print "\" fill=\"magenta\" fill-opacity=\"0.2\" />"
         #       end
         #    }
         # end

         io.print "</svg>"
      end
   end

end


