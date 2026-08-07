#===============================================================================
#
#===============================================================================
class MoveSelectionSprite < Sprite
    attr_reader :preselected
    attr_reader :index
  
    def initialize(viewport = nil, fifthmove = false)
      super(viewport)
      @movesel = AnimatedBitmap.new("Graphics/UI/Summary/cursor_move")
      @frame = 0
      @index = 0
      @fifthmove = fifthmove
      @preselected = false
      @updating = false
      refresh
    end
  
    def dispose
      @movesel.dispose
      super
    end
  
    def index=(value)
      @index = value
      refresh
    end
  
    def preselected=(value)
      @preselected = value
      refresh
    end
  
    def refresh
      w = @movesel.width
      h = @movesel.height / 2
      self.x = 240 + 12
      self.y =  34 + (self.index * 68)
      self.bitmap = @movesel.bitmap
      if self.preselected
        self.src_rect.set(0, h, w, h)
      else
        self.src_rect.set(0, 0, w, h)
      end
    end
  
    def update
      @updating = true
      super
      @movesel.update
      @updating = false
      refresh
    end
  end
  #===============================================================================
  #
  #===============================================================================
  class PokemonSummary_Scene
    MARK_WIDTH  = 16
    MARK_HEIGHT = 16
  
    def pbUpdate
      pbUpdateSpriteHash(@sprites)
    end
  
    def pbStartScene(party, partyindex, inbattle = false)
      @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
      @viewport.z = 99999
      @party      = party
      @partyindex = partyindex
      @pokemon    = @party[@partyindex]
      @inbattle   = inbattle
      @page = 1
	    @pageTwoMode = 1				  
      @typebitmap    = AnimatedBitmap.new(_INTL("Graphics/UI/types"))
	    @markingbitmap = AnimatedBitmap.new("Graphics/UI/Summary/markings")																				
      @sprites = {}
      @sprites["background"] = IconSprite.new(0, 0, @viewport)
      @sprites["overlay_shiny"] = IconSprite.new(0, 36, @viewport)
      @sprites["overlay_shiny"].setBitmap("Graphics/UI/Summary/overlay_shiny")
      @sprites["overlay_shiny"].src_rect.height = @sprites["overlay_shiny"].bitmap.height / 2
      @sprites["pokemon"] = PokemonSprite.new(@viewport)
      @sprites["pokemon"].setOffset(PictureOrigin::CENTER)
      @sprites["pokemon"].x = 104 + 2
      @sprites["pokemon"].y = 206 - 46
      @sprites["pokemon"].mirror = true
      @sprites["pokemon"].setPokemonBitmap(@pokemon)
      @sprites["pokeicon"] = PokemonIconSprite.new(@pokemon, @viewport)
      @sprites["pokeicon"].setOffset(PictureOrigin::CENTER)
      @sprites["pokeicon"].x       = 46
      @sprites["pokeicon"].y       = 92 - 18
      @sprites["pokeicon"].mirror = true
      @sprites["pokeicon"].visible = false
      @sprites["itemicon"] = ItemIconSprite.new(30 + 454 , 320 - 92, @pokemon.item_id, @viewport)
      @sprites["itemicon"].blankzero = true
      @sprites["overlay"] = BitmapSprite.new(Graphics.width, Graphics.height, @viewport)
      pbSetSystemFont(@sprites["overlay"].bitmap)
      @sprites["movepresel"] = MoveSelectionSprite.new(@viewport)
      @sprites["movepresel"].visible     = false
      @sprites["movepresel"].preselected = true
      @sprites["movesel"] = MoveSelectionSprite.new(@viewport)
      @sprites["movesel"].visible = false
      @sprites["markingbg"] = Window_AdvancedTextPokemon.newWithSize("", Graphics.width - 132, Graphics.height - 288, 132, 288, @viewport)
      @sprites["markingbg"].visible = false
      @sprites["markingbg"].setSkin(MessageConfig.pbGetSystemFrame)
      @sprites["markingoverlay"] = BitmapSprite.new(Graphics.width, Graphics.height, @viewport)
      @sprites["markingoverlay"].visible = false
      @sprites["markingoverlay"].z = @viewport.z + 1
      pbSetSystemFont(@sprites["markingoverlay"].bitmap)
      @sprites["markingsel"] = IconSprite.new(0, 0, @viewport)
      @sprites["markingsel"].setBitmap("Graphics/UI/sel_arrow")
      @sprites["markingsel"].visible = false
      @sprites["markingsel"].z = @viewport.z + 1
      @sprites["markingbitmap_2"] = IconSprite.new(0, 0, @viewport)
      @sprites["markingbitmap_2"].setBitmap("Graphics/UI/Summary/markings_2")
      @sprites["markingbitmap_2"].visible = false						 
      @sprites["messagebox"] = Window_AdvancedTextPokemon.new("")
      @sprites["messagebox"].viewport       = @viewport
      @sprites["messagebox"].visible        = false
      @sprites["messagebox"].letterbyletter = true
      pbBottomLeftLines(@sprites["messagebox"], 2)
      @nationalDexList = [:NONE]
      GameData::Species.each_species { |s| @nationalDexList.push(s.species) }
      drawPage(@page)
      pbFadeInAndShow(@sprites) { pbUpdate }
    end
  
    def pbStartForgetScene(party, partyindex, move_to_learn)
      @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
      @viewport.z = 99999
      @party      = party
      @partyindex = partyindex
      @pokemon    = @party[@partyindex]
      @page = 3
      @typebitmap = AnimatedBitmap.new(_INTL("Graphics/UI/types"))
      @sprites = {}
      @sprites["background"] = IconSprite.new(0, 0, @viewport)
      @sprites["overlay_shiny"] = IconSprite.new(0, 36, @viewport)
      @sprites["overlay_shiny"].setBitmap("Graphics/UI/Summary/overlay_shiny")
      @sprites["overlay_shiny"].src_rect.height = @sprites["overlay_shiny"].bitmap.height / 2
      @sprites["overlay"] = BitmapSprite.new(Graphics.width, Graphics.height, @viewport)
      pbSetSystemFont(@sprites["overlay"].bitmap)
      @sprites["pokeicon"] = PokemonIconSprite.new(@pokemon, @viewport)
      @sprites["pokeicon"].setOffset(PictureOrigin::CENTER)
      @sprites["pokeicon"].x       = 46
      @sprites["pokeicon"].y       = 92 - 18
      @sprites["movesel"] = MoveSelectionSprite.new(@viewport, !move_to_learn.nil?)
      @sprites["movesel"].visible = false
      @sprites["movesel"].visible = true
      @sprites["movesel"].index   = 0
      new_move = (move_to_learn) ? Pokemon::Move.new(move_to_learn) : nil
      drawSelectedMove(new_move, @pokemon.moves[0])
      pbFadeInAndShow(@sprites)
    end
  
    def pbEndScene
      pbFadeOutAndHide(@sprites) { pbUpdate }
      pbDisposeSpriteHash(@sprites)
      @typebitmap.dispose
      @markingbitmap&.dispose						 
      @viewport.dispose
    end
  
    def pbDisplay(text)
      @sprites["messagebox"].text = text
      @sprites["messagebox"].visible = true
      pbPlayDecisionSE
      loop do
        Graphics.update
        Input.update
        pbUpdate
        if @sprites["messagebox"].busy?
          if Input.trigger?(Input::USE)
            pbPlayDecisionSE if @sprites["messagebox"].pausing?
            @sprites["messagebox"].resume
          end
        elsif Input.trigger?(Input::USE) || Input.trigger?(Input::BACK)
          break
        end
      end
      @sprites["messagebox"].visible = false
    end
  
    def pbConfirm(text)
      ret = -1
      @sprites["messagebox"].text    = text
      @sprites["messagebox"].visible = true
      using(cmdwindow = Window_CommandPokemon.new([_INTL("Yes"), _INTL("No")])) do
        cmdwindow.z       = @viewport.z + 1
        cmdwindow.visible = false
        pbBottomRight(cmdwindow)
        cmdwindow.y -= @sprites["messagebox"].height
        loop do
          Graphics.update
          Input.update
          cmdwindow.visible = true if !@sprites["messagebox"].busy?
          cmdwindow.update
          pbUpdate
          if !@sprites["messagebox"].busy?
            if Input.trigger?(Input::BACK)
              ret = false
              break
            elsif Input.trigger?(Input::USE) && @sprites["messagebox"].resume
              ret = (cmdwindow.index == 0)
              break
            end
          end
        end
      end
      @sprites["messagebox"].visible = false
      return ret
    end
  
    def pbShowCommands(commands, index = 0)
      ret = -1
      using(cmdwindow = Window_CommandPokemon.new(commands)) do
        cmdwindow.z = @viewport.z + 1
        cmdwindow.index = index
        pbBottomRight(cmdwindow)
        loop do
          Graphics.update
          Input.update
          cmdwindow.update
          pbUpdate
          if Input.trigger?(Input::BACK)
            pbPlayCancelSE
            ret = -1
            break
          elsif Input.trigger?(Input::USE)
            pbPlayDecisionSE
            ret = cmdwindow.index
            break
          end
        end
      end
      return ret     
    end

    def drawMarkings(bitmap, x, y)
      mark_variants = @markingbitmap.bitmap.height / MARK_HEIGHT
      markings = @pokemon.markings
      markrect = Rect.new(0, 0, MARK_WIDTH, MARK_HEIGHT)
      (@markingbitmap.bitmap.width / MARK_WIDTH).times do |i|
        markrect.x = i * MARK_WIDTH
        markrect.y = [(markings[i] || 0), mark_variants - 1].min * MARK_HEIGHT
        bitmap.blt(x, y + (i * MARK_WIDTH), @markingbitmap.bitmap, markrect)
      end
    end

    def drawShinyOverlay(bitmap, type, visible)
      @sprites["overlay_shiny"].src_rect.y = (type == 1) ? 0 : @sprites["overlay_shiny"].bitmap.height / type
      if visible
       @sprites["overlay_shiny"].visible = true
      else
       @sprites["overlay_shiny"].visible = false
      end
    end
  
    def drawPage(page)
      if @pokemon.egg?
        drawPageOneEgg
        return
      end
      @sprites["pokemon"].setPokemonBitmap(@pokemon)
      @sprites["pokeicon"].pokemon = @pokemon
      @sprites["itemicon"].item = @pokemon.item_id
      overlay = @sprites["overlay"].bitmap
      overlay.clear
      base   = Color.new(248, 248, 248)
      shadow = Color.new(96, 96, 96)
      # Set background image
      @sprites["background"].setBitmap("Graphics/UI/Summary/bg_#{page}")
      # Set different overlay for shiny Pokémon
      drawShinyOverlay(overlay, 1, @pokemon.shiny?)
      imagepos = []
      # Show the Poké Ball containing the Pokémon
      ballimage = sprintf("Graphics/UI/Summary/icon_ball_%s", @pokemon.poke_ball)
      imagepos.push([ballimage, 14 + 194, 60 + 160])
      # Show status/fainted/Pokérus infected icon
      status = -1
      if @pokemon.fainted?
        status = GameData::Status.count - 1
      elsif @pokemon.status != :NONE
        status = GameData::Status.get(@pokemon.status).icon_position
      elsif @pokemon.pokerusStage == 1
        status = GameData::Status.count
      end
      if status >= 0
        imagepos.push(["Graphics/UI/statuses", 124 + 78, 100 + 102, 0, 16 * status, 44, 16])
      end
      # Show Pokérus cured icon
      if @pokemon.pokerusStage == 2
        imagepos.push(["Graphics/UI/Summary/icon_pokerus", 176 + 34, 100 - 16])
      end
      # Show shininess star
      imagepos.push(["Graphics/UI/shiny", 2 + 208, 134 - 66]) if @pokemon.shiny?
      # Draw all images
      pbDrawImagePositions(overlay, imagepos)
      # Write various bits of text
      pagename = [_INTL("Pokémon Info"),
                  _INTL("Pokémon Skills"),
                  _INTL("Known Moves"),][page - 1]
      textpos = [
        [pagename, 26 - 18, 22 - 16, :left, base, shadow],
        [@pokemon.name, 46 + 30, 68 - 26, :left, base, shadow],
        [_INTL("Lv{1}", @pokemon.level.to_s), 8, 42, :left, base, shadow]
      ]
      # Write the gender symbol
      if @pokemon.male?
        textpos.push([_INTL("♂"), 178 + 68, 68 - 26, :right, Color.new(160, 192, 240), Color.new(48, 80, 200)])
      elsif @pokemon.female?
        textpos.push([_INTL("♀"), 178 + 68, 68 - 26, :right, Color.new(259, 189, 115), Color.new(231, 8, 8)])
      end
      if page == 1
        @sprites["itemicon"].visible = true
      else
        @sprites["itemicon"].visible = false
      end
      # Write the page info
      pageinfo = [_INTL("Options"),
                  _INTL("EV & IV"),
                  _INTL("Details"),][page - 1]
      if (Settings::SUMMARY_EV_IV and @pageTwoMode == -1)
        pageinfo = _INTL("Stat")
      else
        pageinfo = _INTL("Options") if (page == 2 && !(Settings::SUMMARY_EV_IV))
      end
      textpos.push([pageinfo, 428, 6, :left, base, shadow])	   
      # Draw all text
      pbDrawTextPositions(overlay, textpos)
      # Draw the Pokémon's markings
      drawMarkings(overlay, 84 + 146, 292 - 226)
      # Draw page-specific information
      case page
      when 1 then drawPageOne
      when 2 then drawPageTwo
      when 3 then drawPageThree
      end
    end
  
    def drawPageOne
      overlay = @sprites["overlay"].bitmap
      base   = Color.new(248, 248, 248)
      shadow = Color.new(120, 128, 144)
      # Write various bits of text
      textpos = [
        [_INTL("Dex No."), 238 + 70, 86 - 40, :center, base, shadow, :outline],
        [_INTL("Species"), 238 + 70, 118 - 40, :center, base, shadow, :outline],
        [@pokemon.speciesName, 435 - 77, 118 - 40, :left, Color.new(64, 64, 64), Color.new(216, 216, 192)],
        [_INTL("Type"), 238 + 70, 150 - 40, :center, base, shadow, :outline],
        [_INTL("OT"), 238 + 70, 182 - 40, :center, base, shadow, :outline],
        [_INTL("ID No."), 238 + 70, 214 - 40, :center, base, shadow, :outline],
        [_INTL("Item"), 308, 206, :center, base, shadow, :outline],
        [_INTL("Trainer Memo"), 86, 270, :center, base, shadow, :outline]
      ]
      # Write the Regional/National Dex number
      dexnum = 0
      dexnumshift = false
      if $player.pokedex.unlocked?(-1)   # National Dex is unlocked
        dexnum = @nationalDexList.index(@pokemon.species_data.species) || 0
        dexnumshift = true if Settings::DEXES_WITH_OFFSETS.include?(-1)
      else
        ($player.pokedex.dexes_count - 1).times do |i|
          next if !$player.pokedex.unlocked?(i)
          num = pbGetRegionalNumber(i, @pokemon.species)
          break if num <= 0
          dexnum = num
          dexnumshift = true if Settings::DEXES_WITH_OFFSETS.include?(i)
          break
        end
      end
      if dexnum <= 0
        textpos.push(["???", 435 - 77, 86 - 40, :left, Color.new(64, 64, 64), Color.new(216, 216, 192)])
      else
        dexnum -= 1 if dexnumshift
        textpos.push([sprintf("%03d", dexnum), 435 - 77, 86 - 40, :left, Color.new(64, 64, 64), Color.new(216, 216, 192)])
      end
      # Write Original Trainer's name and ID number
      if @pokemon.owner.name.empty?
        textpos.push([_INTL("RENTAL"), 435 - 77, 182 - 40, :left, Color.new(64, 64, 64), Color.new(216, 216, 192)])
        textpos.push(["?????", 435 - 77, 214 - 40, :left, Color.new(64, 64, 64), Color.new(216, 216, 192)])
      else
        ownerbase   = Color.new(64, 64, 64)
        ownershadow = Color.new(216, 216, 192)
        case @pokemon.owner.gender
        when 0
          ownerbase = Color.new(160, 192, 240)
          ownershadow = Color.new(48, 80, 200)
        when 1
          ownerbase = Color.new(259, 189, 115)
          ownershadow = Color.new(231, 8, 8)
        end
        textpos.push([@pokemon.owner.name, 435 - 77, 182 - 40, :left, ownerbase, ownershadow])
        textpos.push([sprintf("%05d", @pokemon.owner.public_id), 435 - 77, 214 - 40, :left,
                      Color.new(64, 64, 64), Color.new(216, 216, 192)])
      end
      # Write the held item's name
      if @pokemon.hasItem?
        textpos.push([@pokemon.item.name, 16 + 250, 358 - 130, :left, Color.new(64, 64, 64), Color.new(216, 216, 192)])
      else
        textpos.push([_INTL("None"), 16 + 250, 358 - 130, :left, Color.new(64, 64, 64), Color.new(216, 216, 192)])
      end
      # Draw all text
      pbDrawTextPositions(overlay, textpos)
      # Write Trainer Memo
      memo = ""
      # Write nature and characteristic
      showNature = !@pokemon.shadowPokemon? || @pokemon.heartStage <= 3
      if showNature
        natureName = @pokemon.nature.name
        memo += _INTL("{1} nature. ", natureName)
        best_stat = nil
        best_iv = 0
        stats_order = [:HP, :ATTACK, :DEFENSE, :SPEED, :SPECIAL_ATTACK, :SPECIAL_DEFENSE]
        start_point = @pokemon.personalID % stats_order.length   # Tiebreaker
        stats_order.length.times do |i|
          stat = stats_order[(i + start_point) % stats_order.length]
          if !best_stat || @pokemon.iv[stat] > @pokemon.iv[best_stat]
            best_stat = stat
            best_iv = @pokemon.iv[best_stat]
          end
        end
        characteristics = {
          :HP              => [_INTL("Loves to eat."),
                               _INTL("Takes plenty of siestas."),
                               _INTL("Nods off a lot."),
                               _INTL("Scatters things often."),
                               _INTL("Likes to relax.")],
          :ATTACK          => [_INTL("Proud of its power."),
                               _INTL("Likes to thrash about."),
                               _INTL("A little quick tempered."),
                               _INTL("Likes to fight."),
                               _INTL("Quick tempered.")],
          :DEFENSE         => [_INTL("Sturdy body."),
                               _INTL("Capable of taking hits."),
                               _INTL("Highly persistent."),
                               _INTL("Good endurance."),
                               _INTL("Good perseverance.")],
          :SPECIAL_ATTACK  => [_INTL("Highly curious."),
                               _INTL("Mischievous."),
                               _INTL("Thoroughly cunning."),
                               _INTL("Often lost in thought."),
                               _INTL("Very finicky.")],
          :SPECIAL_DEFENSE => [_INTL("Strong willed."),
                               _INTL("Somewhat vain."),
                               _INTL("Strongly defiant."),
                               _INTL("Hates to lose."),
                               _INTL("Somewhat stubborn.")],
          :SPEED           => [_INTL("Likes to run."),
                               _INTL("Alert to sounds."),
                               _INTL("Impetuous and silly."),
                               _INTL("Somewhat of a clown."),
                               _INTL("Quick to flee.")]
        }
        memo += characteristics[best_stat][best_iv % 5] + "\n"
      end
      # Write how Pokémon was hatched
      if @pokemon.obtain_method == 1
        memo += _INTL("Egg hatched in ")
        mapname = pbGetMapNameFromId(@pokemon.hatched_map)
        mapname = _INTL("Faraway place") if nil_or_empty?(mapname)
        memo += sprintf("%s", mapname)
        if @pokemon.timeEggHatched
          date  = @pokemon.timeEggHatched.day
          month = pbGetMonthName(@pokemon.timeEggHatched.mon)
          year  = @pokemon.timeEggHatched.year
          memo += _INTL(" on {1} {2}, {3}", date, month, year)
        end
        memo += ".\n"
      else
        mettext = [_INTL("Met at Lv. {1}", @pokemon.obtain_level),
                  "",
                  _INTL("Traded at Lv. {1}", @pokemon.obtain_level),
                  "",
                  _INTL("Had a fateful encounter at Lv. {1}", @pokemon.obtain_level)][@pokemon.obtain_method]
        memo += sprintf(mettext) if mettext && mettext != ""
        # Write map name Pokémon was received on
        mapname = pbGetMapNameFromId(@pokemon.obtain_map)
        mapname = @pokemon.obtain_text if @pokemon.obtain_text && !@pokemon.obtain_text.empty?
        mapname = _INTL("Faraway place") if nil_or_empty?(mapname)
        memo += sprintf(" in %s", mapname)
        # Write date received
        if @pokemon.timeReceived
          date  = @pokemon.timeReceived.day
          month = pbGetMonthName(@pokemon.timeReceived.mon)
          year  = @pokemon.timeReceived.year
          memo += _INTL(" on {1} {2}, {3}", date, month, year)
        end
        memo += _INTL(".\n")
      end
      # Write all text
      drawFormattedTextEx(overlay, 232 - 216, 86 + 214, 268 + 220, memo, Color.new(64, 64, 64), Color.new(216, 216, 192), 28)
      # Draw Pokémon type(s)
      @pokemon.types.each_with_index do |type, i|
        type_number = GameData::Type.get(type).icon_position
        type_rect = Rect.new(0, type_number * 28, 64, 28)
        type_x = (@pokemon.types.length == 1) ? 402 - 44 : 358 + (72 * i)
        overlay.blt(type_x, 146 - 40, @typebitmap.bitmap, type_rect)
      end
    end
  
    def drawPageOneEgg
      @sprites["itemicon"].item = @pokemon.item_id
      overlay = @sprites["overlay"].bitmap
      overlay.clear
      base   = Color.new(248, 248, 248)
      shadow = Color.new(120, 128, 144)
      drawShinyOverlay(overlay, 1, false)
      # Set background image
      @sprites["background"].setBitmap("Graphics/UI/Summary/bg_egg")
      imagepos = []
      # Show the Poké Ball containing the Pokémon
      ballimage = sprintf("Graphics/UI/Summary/icon_ball_%s", @pokemon.poke_ball)
      imagepos.push([ballimage, 14 + 194, 60 + 160])
      # Draw all images
      pbDrawImagePositions(overlay, imagepos)
      # Write various bits of text
      textpos = [
        [_INTL("Name"), 238 + 70, 86 - 40, :center, base, shadow, :outline],
        [_INTL("State"), 238 + 70, 118 - 40, :center, base, shadow, :outline],
        [_INTL("Pokémon Info"), 26 - 18, 22 - 16, :left, base, shadow],
        [@pokemon.name, 435 - 77, 86 - 40, :left, Color.new(64, 64, 64), Color.new(216, 216, 192)],
        [_INTL("Item"), 308, 206, :center, base, shadow, :outline],
        [_INTL("Trainer Memo"), 86, 270, :center, base, shadow, :outline]
      ]
      # Write the held item's name
      if @pokemon.hasItem?
        textpos.push([@pokemon.item.name, 16 + 250, 358 - 130, :left, Color.new(64, 64, 64), Color.new(216, 216, 192)])
      else
        textpos.push([_INTL("None"), 16 + 250, 358 - 130, :left, Color.new(64, 64, 64), Color.new(216, 216, 192)])
      end
      # Write the page info
      textpos.push([_INTL("Options"), 426, 6, 0, base, shadow])
      # Draw all text
      pbDrawTextPositions(overlay, textpos)
      # Write Egg Watch blurb
      eggstate = _INTL("It looks like this Egg will take a long time to hatch.")
      eggstate = _INTL("What will hatch from this? It doesn't seem close to hatching.") if @pokemon.steps_to_hatch < 10_200
      eggstate = _INTL("It appears to move occasionally. It may be close to hatching.") if @pokemon.steps_to_hatch < 2550
      eggstate = _INTL("Sounds can be heard coming from inside! It will hatch soon!") if @pokemon.steps_to_hatch < 1275
      drawTextEx(overlay, 266, 108, 238, 3, eggstate, Color.new(64, 64, 64), Color.new(216, 216, 192))
      memo = ""
      # Write map name egg was received on
      mapname = pbGetMapNameFromId(@pokemon.obtain_map)
      mapname = @pokemon.obtain_text if @pokemon.obtain_text && !@pokemon.obtain_text.empty?
      if mapname && mapname != ""
        memo += _INTL("A mysterious Pokémon Egg received from {1}", mapname)
      else
        memo += _INTL("A mysterious Pokémon Egg", mapname)
      end
      # Write date received
      if @pokemon.timeReceived
        date  = @pokemon.timeReceived.day
        month = pbGetMonthName(@pokemon.timeReceived.mon)
        year  = @pokemon.timeReceived.year
        memo += _INTL(" on {1} {2}, {3}", date, month, year)
      end
      memo += "."
      # Write all text
      drawFormattedTextEx(overlay, 232 - 216, 86 + 214, 268 + 220, memo, Color.new(64, 64, 64), Color.new(216, 216, 192), 28)
      # Draw the Pokémon's markings
      drawMarkings(overlay, 84 + 146, 292 - 226)
    end
  
    def drawPageTwo
      overlay = @sprites["overlay"].bitmap
      base   = Color.new(248, 248, 248)
      shadow = Color.new(120, 128, 144)
      # If a Shadow Pokémon, draw the heart gauge area and bar
      if @pokemon.shadowPokemon?
        shadowfract = @pokemon.heart_gauge.to_f / @pokemon.max_gauge_size
        imagepos = [
          ["Graphics/UI/Summary/overlay_shadow", 12, 272],
          ["Graphics/UI/Summary/overlay_shadowbar", 340, 304, 0, 0, (shadowfract * 158).floor, -1]
        ]
        pbDrawImagePositions(overlay, imagepos)
      end
      # Write various bits of text
      textpos = [
        [_INTL("HP"), 292 + 16, 82 - 36, :center, base, shadow, :outline],
        [_INTL("Attack"), 248 + 60, 126 - 38, :center, base, shadow, :outline],
        [_INTL("Defense"), 248 + 60, 158 - 38, :center, base, shadow, :outline],
        [_INTL("Sp. Atk"), 248 + 60, 190 - 38, :center, base, shadow, :outline],
        [_INTL("Sp. Def"), 248 + 60, 222 - 38, :center, base, shadow, :outline],
        [_INTL("Speed"), 248 + 60, 254 - 38, :center, base, shadow, :outline],
        [_INTL("Ability"), 224 - 150, 290 + 14, :center, base, shadow, :outline]
      ]
      if @pageTwoMode == 1
        drawPageTwoStats
      else
        drawPageTwoEVIV
      end
      # Draw ability name and description
      ability = @pokemon.ability
      hidden_ability = (@pokemon.hasHiddenAbility? && Settings::SUMMARY_HIDDEN_ABILITY)
      ability_base =  hidden_ability ? Color.new(160, 64, 160) : Color.new(64, 64, 64)
      ability_shadow = hidden_ability ? Color.new(240, 176, 240) : Color.new(216, 216, 192)
      if ability
        textpos.push([ability.name, 362 - 220, 290 + 14, :left, ability_base, ability_shadow])
        drawFormattedTextEx(overlay, 224 - 208, 322 + 10, 282 + 206, ability.description, Color.new(64, 64, 64), Color.new(216, 216, 192), 28)
      end
      # Write Exp text OR heart gauge message (if a Shadow Pokémon)
      if @pokemon.shadowPokemon?
        heartmessage = [_INTL("The door to its heart is open! Undo the lock!"),
                        _INTL("The door to its heart is almost fully open."),
                        _INTL("The door to its heart is nearly open."),
                        _INTL("The door to its heart is opening wider."),
                        _INTL("The door to its heart is opening up."),
                        _INTL("The door to its heart is tightly shut.")][@pokemon.heartStage]
        drawFormattedTextEx(overlay, 234 - 218, 308 - 30, 264 + 224, heartmessage, Color.new(64, 64, 64), Color.new(216, 216, 192))
      else
        endexp = @pokemon.growth_rate.minimum_exp_for_level(@pokemon.level + 1)
        textpos.push([_INTL("Exp. Points"), 238 - 222, 246 + 30, :left, Color.new(64, 64, 64), Color.new(216, 216, 192)])
        textpos.push([@pokemon.exp.to_s_formatted, 488 - 236, 278 - 2, :right, Color.new(64, 64, 64), Color.new(216, 216, 192)])
        textpos.push([_INTL("To Next Lv."), 238 + 30, 310 - 34, :left, Color.new(64, 64, 64), Color.new(216, 216, 192)])
        textpos.push([(endexp - @pokemon.exp).to_s_formatted, 488 + 16, 342 - 66, :right, Color.new(64, 64, 64), Color.new(216, 216, 192)])
      end
      # Draw all text
      pbDrawTextPositions(overlay, textpos)
      # Draw HP bar
      if @pokemon.hp > 0
        w = @pokemon.hp * 96 / @pokemon.totalhp.to_f
        w = 1 if w < 1
        w = ((w / 2).round) * 2
        hpzone = 0
        hpzone = 1 if @pokemon.hp <= (@pokemon.totalhp / 2).floor
        hpzone = 2 if @pokemon.hp <= (@pokemon.totalhp / 4).floor
        imagepos = [
          ["Graphics/UI/Summary/overlay_hp", 360 + 40, 110 - 36, 0, hpzone * 6, w, 6]
        ]
        pbDrawImagePositions(overlay, imagepos)
      end
      # Draw Exp bar
      if @pokemon.level < GameData::GrowthRate.max_level
        w = @pokemon.exp_fraction * 128
        w = ((w / 2).round) * 2
        pbDrawImagePositions(overlay,
                            [["Graphics/UI/Summary/overlay_exp", 362 + 6, 372 - 68, 0, 0, w, 6]]) if !@pokemon.shadowPokemon?
      end
      # Draw IV Ratings
      drawIVRating(@pokemon, overlay, 370, 50) if Settings::SUMMARY_IV_RATINGS
    end

    def drawIVRating(pokemon, overlay, xpos, ypos)
      return if !pokemon
      imagepos = []
      textpos = []
      overlay_path  = "Graphics/UI/Summary/overlay_IVRating"
      maxIV = Pokemon::IV_STAT_LIMIT
      i = 0
      GameData::Stat.each_main do |s|
        stat = pokemon.iv[s.id]
        case stat
        when maxIV     then icon = 5  # 31 IV
        when maxIV - 1 then icon = 4  # 30 IV
        when 0         then icon = 0  #  0 IV
        else
          if stat > (maxIV - (maxIV / 4).floor)
            icon = 3 # 25-29 IV
          elsif stat > (maxIV - (maxIV / 2).floor)
            icon = 2 # 16-24 IV
          else
            icon = 1 #  1-15 IV
          end
        end
        ratingBase = [
          Color.new(255, 149, 128),
          Color.new(102, 204, 255),
          Color.new(82, 230, 69),
          Color.new(255, 207, 64),
          Color.new(255, 106, 76),
          Color.new(240, 176, 240)
        ][icon]
        ratingIV = ["F", "D", "C", "B", "A", "S"][icon]
        imagepos.push([overlay_path, xpos, ypos + (i * 32)])
        textpos.push([_INTL(ratingIV), (xpos + 20), (ypos - 4) + (i * 32), :center, ratingBase, Color.new(120, 128, 144), :outline])
        if s.id == :HP
          ypos += 10 
        end
        i += 1
      end
      pbDrawImagePositions(overlay, imagepos)
      pbDrawTextPositions(overlay, textpos)
    end

    def drawPageTwoStats
      overlay = @sprites["overlay"].bitmap
      base   = Color.new(64, 64, 64)
      shadow = Color.new(216, 216, 192)
      # Determine which stats are boosted and lowered by the Pokémon's nature
      statsbases = {}
      GameData::Stat.each_main { |s| statsbases[s.id] = base}
      if !@pokemon.shadowPokemon? || @pokemon.heartStage <= 3
        @pokemon.nature_for_stats.stat_changes.each do |change|
          statsbases[change[0]] = Color.new(232, 48, 0) if change[1] > 0
          statsbases[change[0]] = Color.new(104, 144, 240) if change[1] < 0
        end
      end
      # Write various bits of text
      textpos = [
        [sprintf("%d/%d", @pokemon.hp, @pokemon.totalhp), 462 + 44, 82 - 36, :right, statsbases[:HP], Color.new(216, 216, 192)],
        [@pokemon.attack.to_s, 456 + 50, 126 - 38, :right, statsbases[:ATTACK], Color.new(216, 216, 192)],
        [@pokemon.defense.to_s, 456 + 50, 158 - 38, :right, statsbases[:DEFENSE], Color.new(216, 216, 192)],
        [@pokemon.spatk.to_s, 456 + 50, 190 - 38, :right, statsbases[:SPECIAL_ATTACK], Color.new(216, 216, 192)],
        [@pokemon.spdef.to_s, 456 + 50, 222 - 38, :right, statsbases[:SPECIAL_DEFENSE], Color.new(216, 216, 192)],
        [@pokemon.speed.to_s, 456 + 50, 254 - 38, :right, statsbases[:SPEED], Color.new(216, 216, 192)]
      ]
      # Draw all text
      pbDrawTextPositions(overlay, textpos)
    end

    def drawPageTwoEVIV
      overlay = @sprites["overlay"].bitmap
      base   = Color.new(64, 64, 64)
      shadow = Color.new(216, 216, 192)
      textpos = [
        [sprintf("%d/%d", @pokemon.ev[:HP], @pokemon.iv[:HP]), 462 + 44, 82 - 36, :right, base, shadow],
        [sprintf("%d/%d", @pokemon.ev[:ATTACK], @pokemon.iv[:ATTACK]), 456 + 50, 126 - 38, :right, base, shadow],
        [sprintf("%d/%d", @pokemon.ev[:DEFENSE], @pokemon.iv[:DEFENSE]), 456 + 50, 158 - 38, :right, base, shadow],
        [sprintf("%d/%d", @pokemon.ev[:SPECIAL_ATTACK], @pokemon.iv[:SPECIAL_ATTACK]), 456 + 50, 190 - 38, :right, base, shadow],
        [sprintf("%d/%d", @pokemon.ev[:SPECIAL_DEFENSE], @pokemon.iv[:SPECIAL_DEFENSE]), 456 + 50, 222 - 38, :right, base, shadow],
        [sprintf("%d/%d", @pokemon.ev[:SPEED], @pokemon.iv[:SPEED]), 456 + 50, 254 - 38, :right,  base, shadow]
      ]
      pbDrawTextPositions(overlay, textpos)
    end
  
    def drawPageThree
      overlay = @sprites["overlay"].bitmap
      moveBase   = Color.new(33, 33, 33)
      moveShadow = Color.new(222, 222, 222)
      ppBase   = [moveBase,                # More than 1/2 of total PP
                  Color.new(239, 222, 0),    # 1/2 of total PP or less
                  Color.new(255, 148, 0),   # 1/4 of total PP or less
                  Color.new(239, 0, 0)]    # Zero PP
      ppShadow = [moveShadow,             # More than 1/2 of total PP
                  Color.new(255, 247, 140),   # 1/2 of total PP or less
                  Color.new(255, 239, 115),   # 1/4 of total PP or less
                  Color.new(247, 222, 156)]   # Zero PP
      @sprites["pokemon"].visible  = true
      @sprites["pokeicon"].visible = false
      textpos  = []
      imagepos = []
      # Write move names, types and PP amounts for each known move
      yPos = 104 - 60
      Pokemon::MAX_MOVES.times do |i|
        move = @pokemon.moves[i]
        if move
          type_number = GameData::Type.get(move.display_type(@pokemon)).icon_position
          imagepos.push(["Graphics/UI/types", 248 + 12, yPos - 4, 0, type_number * 28, 64, 28])
          textpos.push([move.name, 316 + 12, yPos + 2, :left, moveBase, moveShadow])
          if move.total_pp > 0
            ppfraction = 0
            if move.pp == 0
              ppfraction = 3
            elsif move.pp * 4 <= move.total_pp
              ppfraction = 2
            elsif move.pp * 2 <= move.total_pp
              ppfraction = 1
            end
            textpos.push([_INTL("PP"), 342 + 76, yPos + 34, :left, ppBase[ppfraction], ppShadow[ppfraction]])
            textpos.push([sprintf("%d/%d", move.pp, move.total_pp), 460 + 44, yPos + 34, :right, ppBase[ppfraction], ppShadow[ppfraction]])
          end
        else
          textpos.push([_INTL("PP"), 342 + 76, yPos + 34, :left, moveBase, moveShadow])
          textpos.push(["-", 316 + 12, yPos + 2, :left, moveBase, moveShadow])
          textpos.push(["--", 442 + 2, yPos + 32, :left, moveBase, moveShadow])
        end
        yPos += 68
      end
      # Draw all text and images
      pbDrawTextPositions(overlay, textpos)
      pbDrawImagePositions(overlay, imagepos)
    end
  
    def drawPageThreeSelecting(move_to_learn)
      overlay = @sprites["overlay"].bitmap
      overlay.clear
      # Set different overlay for shiny Pokémon
      drawShinyOverlay(overlay, 2, @pokemon.shiny?)  
      base   = Color.new(248, 248, 248)
      shadow = Color.new(120, 128, 144)
      moveBase   = Color.new(33, 33, 33)
      moveShadow = Color.new(222, 222, 222)
      ppBase   = [moveBase,                # More than 1/2 of total PP
                  Color.new(239, 222, 0),    # 1/2 of total PP or less
                  Color.new(255, 148, 0),   # 1/4 of total PP or less
                  Color.new(239, 0, 0)]    # Zero PP
      ppShadow = [moveShadow,             # More than 1/2 of total PP
                  Color.new(255, 247, 140),   # 1/2 of total PP or less
                  Color.new(255, 239, 115),   # 1/4 of total PP or less
                  Color.new(247, 222, 156)]   # Zero PP
      # Set background image
      if move_to_learn
        @sprites["background"].setBitmap("Graphics/UI/Summary/bg_learnmove")
      else
        @sprites["background"].setBitmap("Graphics/UI/Summary/bg_movedetail")
      end
      # Write various bits of text
      textpos = [
        [_INTL("Known Moves"), 26 - 18, 22 - 16, :left, base, Color.new(96, 96, 96)],
        [_INTL("Switch"), 426, 6, :left, base, Color.new(96, 96, 96)],
        [_INTL("Power"), 20 + 34, 160 - 42, :center, base, shadow, :outline],
        [_INTL("Accuracy"), 20 + 34, 192 - 38, :center, base, shadow, :outline],
        [_INTL("Effect"), 20 + 34, 192 - 4, :center, base, shadow, :outline],
        [@pokemon.name, 92, 42, :left, Color.new(255, 255, 255), Color.new(99, 99, 99)]
      ]
      # Write the gender symbol (Changed to match FRLG)
      if @pokemon.male?
        textpos.push([_INTL("♂"), 244, 42, :right, Color.new(160, 192, 240), Color.new(48, 80, 200)])
      elsif @pokemon.female?
        textpos.push([_INTL("♀"), 244, 42, :right, Color.new(259, 189, 115), Color.new(231, 8, 8)])
      end
      imagepos = []
      # Show shininess star (Changed to match FRLG)
      if @pokemon.shiny?
        imagepos.push([sprintf("Graphics/UI/shiny"), 92, 76])
      end 
      # Write move names, types and PP amounts for each known move
      yPos = 104 - 60
      limit = (move_to_learn) ? Pokemon::MAX_MOVES + 1 : Pokemon::MAX_MOVES
      limit.times do |i|
        move = @pokemon.moves[i]
        if i == Pokemon::MAX_MOVES
          move = move_to_learn
        end
        if move
          type_number = GameData::Type.get(move.display_type(@pokemon)).icon_position
          imagepos.push(["Graphics/UI/types", 248 + 12, yPos - 4, 0, type_number * 28, 64, 28])
          textpos.push([move.name, 316 + 12, yPos + 2, :left, moveBase, moveShadow])
          if move.total_pp > 0
            ppfraction = 0
            if move.pp == 0
              ppfraction = 3
            elsif move.pp * 4 <= move.total_pp
              ppfraction = 2
            elsif move.pp * 2 <= move.total_pp
              ppfraction = 1
            end
            textpos.push([_INTL("PP"), 342 + 76, yPos + 34, :left, ppBase[ppfraction], ppShadow[ppfraction]])
            textpos.push([sprintf("%d/%d", move.pp, move.total_pp), 460 + 44, yPos + 34, :right, ppBase[ppfraction], ppShadow[ppfraction]])
          end
        else
          textpos.push([_INTL("PP"), 342 + 76, yPos + 34, :left, moveBase, moveShadow])
          textpos.push(["-", 316 + 12, yPos + 2, :left, moveBase, moveShadow])
          textpos.push(["--", 442 + 2, yPos + 32, :left, moveBase, moveShadow])
        end
        yPos += 68
      end
      # Draw all text and images
      pbDrawTextPositions(overlay, textpos)
      pbDrawImagePositions(overlay, imagepos)
      # Draw Pokémon's type icon(s)
      @pokemon.types.each_with_index do |type, i|
        type_number = GameData::Type.get(type).icon_position
        type_rect = Rect.new(0, type_number * 28, 64, 28)
        type_x = (@pokemon.types.length == 1) ? 130 - 22 : 108 + (72 * i)
        overlay.blt(type_x, 78 - 8, @typebitmap.bitmap, type_rect)
      end
    end
  
    def drawSelectedMove(move_to_learn, selected_move)
      # Draw all of page three, except selected move's details
      drawPageThreeSelecting(move_to_learn)
      # Set various values
      overlay = @sprites["overlay"].bitmap
      base = Color.new(66, 66, 66)
      shadow = Color.new(222, 222, 198)
      @sprites["pokemon"].visible = false if @sprites["pokemon"]
      @sprites["pokeicon"].pokemon = @pokemon
      @sprites["pokeicon"].visible = true
      textpos = []
      # Write power and accuracy values for selected move
      case selected_move.display_damage(@pokemon)
      when 0 then textpos.push(["---", 216 - 70, 160 - 42, :center, base, shadow])   # Status move
      when 1 then textpos.push(["???", 216 - 70, 160 - 42, :center, base, shadow])   # Variable power move
      else        textpos.push([selected_move.display_damage(@pokemon).to_s, 216 - 70, 160 - 42, :center, base, shadow])
      end
      if selected_move.display_accuracy(@pokemon) == 0
        textpos.push(["---", 216 - 70, 192 - 38, :center, base, shadow])
      else
        textpos.push(["#{selected_move.display_accuracy(@pokemon)}%", 216 - 70, 192 - 38, :center, base, shadow])
      end
      # Draw all text
      pbDrawTextPositions(overlay, textpos)
      # Draw selected move's damage category icon
      imagepos = [["Graphics/UI/category", 166 + 14, 124 - 10, 0, selected_move.display_category(@pokemon) * 28, 64, 28]]
      pbDrawImagePositions(overlay, imagepos)
      # Draw selected move's description
      drawTextEx(overlay, 4 + 4, 224 - 6, 230, 5, selected_move.description, base, shadow)
    end
  
    def pbGoToPrevious
      newindex = @partyindex
      while newindex > 0
        newindex -= 1
        if @party[newindex] && (@page == 1 || !@party[newindex].egg?)
          @partyindex = newindex
          break
        end
      end
    end
  
    def pbGoToNext
      newindex = @partyindex
      while newindex < @party.length - 1
        newindex += 1
        if @party[newindex] && (@page == 1 || !@party[newindex].egg?)
          @partyindex = newindex
          break
        end
      end
    end
  
    def pbChangePokemon
      @pokemon = @party[@partyindex]
      @sprites["pokemon"].setPokemonBitmap(@pokemon)
      @sprites["itemicon"].item = @pokemon.item_id
      pbSEStop
      @pokemon.play_cry
    end
  
    def pbMoveSelection
      @sprites["movesel"].visible = true
      @sprites["movesel"].index   = 0
      selmove    = 0
      oldselmove = 0
      switching = false
      drawSelectedMove(nil, @pokemon.moves[selmove])
      loop do
        Graphics.update
        Input.update
        pbUpdate
        if @sprites["movepresel"].index == @sprites["movesel"].index
          @sprites["movepresel"].z = @sprites["movesel"].z + 1
        else
          @sprites["movepresel"].z = @sprites["movesel"].z
        end
        if Input.trigger?(Input::BACK)
          (switching) ? pbPlayCancelSE : pbPlayCloseMenuSE
          break if !switching
          @sprites["movepresel"].visible = false
          switching = false
        elsif Input.trigger?(Input::USE)
          pbPlayDecisionSE
          if selmove == Pokemon::MAX_MOVES
            break if !switching
            @sprites["movepresel"].visible = false
            switching = false
          elsif !@pokemon.shadowPokemon?
            if switching
              tmpmove                    = @pokemon.moves[oldselmove]
              @pokemon.moves[oldselmove] = @pokemon.moves[selmove]
              @pokemon.moves[selmove]    = tmpmove
              @sprites["movepresel"].visible = false
              switching = false
              drawSelectedMove(nil, @pokemon.moves[selmove])
            else
              @sprites["movepresel"].index   = selmove
              @sprites["movepresel"].visible = true
              oldselmove = selmove
              switching = true
            end
          end
        elsif Input.trigger?(Input::UP)
          selmove -= 1
          if selmove < Pokemon::MAX_MOVES && selmove >= @pokemon.numMoves
            selmove = @pokemon.numMoves - 1
          end
          selmove = 0 if selmove >= Pokemon::MAX_MOVES
          selmove = @pokemon.numMoves - 1 if selmove < 0
          @sprites["movesel"].index = selmove
          pbPlayCursorSE
          drawSelectedMove(nil, @pokemon.moves[selmove])
        elsif Input.trigger?(Input::DOWN)
          selmove += 1
          selmove = 0 if selmove < Pokemon::MAX_MOVES && selmove >= @pokemon.numMoves
          selmove = 0 if selmove >= Pokemon::MAX_MOVES
          selmove = Pokemon::MAX_MOVES if selmove < 0
          @sprites["movesel"].index = selmove
          pbPlayCursorSE
          drawSelectedMove(nil, @pokemon.moves[selmove])
        end
      end
      @sprites["movesel"].visible = false
    end

    def pbMarking(pokemon)
      @sprites["markingbg"].visible      = true
      @sprites["markingoverlay"].visible = true
      @sprites["markingsel"].visible     = true
      base   = Color.new(80, 80, 80)
      shadow = Color.new(160, 160, 168)
      ret = pokemon.markings.clone
      markings = pokemon.markings.clone
      mark_variants = @sprites["markingbitmap_2"].height / MARK_HEIGHT
      index = 0				  
      redraw = true
      markrect = Rect.new(0, 0, MARK_WIDTH, MARK_HEIGHT)
      loop do
        # Redraw the markings and text
        if redraw
          @sprites["markingoverlay"].bitmap.clear
          (@sprites["markingbitmap_2"].bitmap.width / MARK_WIDTH).times do |i|
            markrect.x = i * MARK_WIDTH
            markrect.y = [(markings[i] || 0), mark_variants - 1].min * MARK_HEIGHT
            @sprites["markingoverlay"].bitmap.blt((Graphics.width - 62) - (MARK_WIDTH / 2), 118 + (32 * i),
                                                   @sprites["markingbitmap_2"].bitmap, markrect)
          end
          textpos = [
            [_INTL("OK"), 366 + 46, 254 + 56, :left, base, shadow],
            [_INTL("Cancel"), 366 + 46, 304 + 38, :left, base, shadow]
          ]
          pbDrawTextPositions(@sprites["markingoverlay"].bitmap, textpos)
          redraw = false
        end
        # Reposition the cursor
        @sprites["markingsel"].x = 396
        @sprites["markingsel"].y = 112 + (32 * index)
        Graphics.update
        Input.update
        pbUpdate
        if Input.trigger?(Input::BACK)
          pbPlayCloseMenuSE
          break
        elsif Input.trigger?(Input::USE)
          pbPlayDecisionSE
          case index
          when 6   # OK
													  
            ret = markings
            break
          when 7   # Cancel
            break
          else
            markings[index] = ((markings[index] || 0) + 1) % mark_variants
            redraw = true
          end
        elsif Input.trigger?(Input::ACTION)
          if index < 6 && markings[index] > 0
            pbPlayDecisionSE
            markings[index] = 0
            redraw = true
          end
        elsif Input.trigger?(Input::UP)
          index -= 1
          if index < 0
            index = 7
          end
          pbPlayCursorSE
        elsif Input.trigger?(Input::DOWN)
          index += 1
          if index > 7
            index = 0
          end
          pbPlayCursorSE
        end
						
      end
      @sprites["markingbg"].visible      = false
      @sprites["markingoverlay"].visible = false
      @sprites["markingsel"].visible     = false
      if pokemon.markings != ret
        pokemon.markings = ret
        return true
      end
      return false
    end
  
    def pbOptions
      dorefresh = false
      commands = []
      cmdGiveItem = -1
      cmdTakeItem = -1
      cmdPokedex  = -1
      cmdMark     = -1
      if !@pokemon.egg?
        commands[cmdGiveItem = commands.length] = _INTL("Give item")
        commands[cmdTakeItem = commands.length] = _INTL("Take item") if @pokemon.hasItem?
        commands[cmdPokedex = commands.length]  = _INTL("View Pokédex") if $player.has_pokedex
      end
      commands[cmdMark = commands.length]       = _INTL("Mark")
      commands[commands.length]                 = _INTL("Cancel")
      command = pbShowCommands(commands)
      if cmdGiveItem >= 0 && command == cmdGiveItem
        item = nil
        pbFadeOutIn do
          scene = PokemonBag_Scene.new
          screen = PokemonBagScreen.new(scene, $bag)
          item = screen.pbChooseItemScreen(proc { |itm| GameData::Item.get(itm).can_hold? })
        end
        dorefresh = pbGiveItemToPokemon(item, @pokemon, self, @partyindex) if item
      elsif cmdTakeItem >= 0 && command == cmdTakeItem
        dorefresh = pbTakeItemFromPokemon(@pokemon, self)
      elsif cmdPokedex >= 0 && command == cmdPokedex
        $player.pokedex.register_last_seen(@pokemon)
        pbFadeOutIn do
          scene = PokemonPokedexInfo_Scene.new
          screen = PokemonPokedexInfoScreen.new(scene)
          screen.pbStartSceneSingle(@pokemon.species)
        end
        dorefresh = true
      elsif cmdMark >= 0 && command == cmdMark
        dorefresh = pbMarking(@pokemon)
      end
      return dorefresh
    end
  
    def pbChooseMoveToForget(move_to_learn)
      new_move = (move_to_learn) ? Pokemon::Move.new(move_to_learn) : nil
      selmove = 0
      maxmove = (new_move) ? Pokemon::MAX_MOVES : Pokemon::MAX_MOVES - 1
      loop do
        Graphics.update
        Input.update
        pbUpdate
        if Input.trigger?(Input::BACK)
          selmove = Pokemon::MAX_MOVES
          pbPlayCloseMenuSE if new_move
          break
        elsif Input.trigger?(Input::USE)
          pbPlayDecisionSE
          break
        elsif Input.trigger?(Input::UP)
          selmove -= 1
          selmove = maxmove if selmove < 0
          if selmove < Pokemon::MAX_MOVES && selmove >= @pokemon.numMoves
            selmove = @pokemon.numMoves - 1
          end
          @sprites["movesel"].index = selmove
          selected_move = (selmove == Pokemon::MAX_MOVES) ? new_move : @pokemon.moves[selmove]
          drawSelectedMove(new_move, selected_move)
        elsif Input.trigger?(Input::DOWN)
          selmove += 1
          selmove = 0 if selmove > maxmove
          if selmove < Pokemon::MAX_MOVES && selmove >= @pokemon.numMoves
            selmove = (new_move) ? maxmove : 0
          end
          @sprites["movesel"].index = selmove
          selected_move = (selmove == Pokemon::MAX_MOVES) ? new_move : @pokemon.moves[selmove]
          drawSelectedMove(new_move, selected_move)
        end
      end
      return (selmove == Pokemon::MAX_MOVES) ? -1 : selmove
    end
  
    def pbScene
      @pokemon.play_cry
      loop do
        Graphics.update
        Input.update
        pbUpdate
        dorefresh = false
        if Input.trigger?(Input::ACTION)
          pbSEStop
          @pokemon.play_cry
        elsif Input.trigger?(Input::BACK)
          pbPlayCloseMenuSE
          break
        elsif Input.trigger?(Input::USE)
          if @page == 3
            pbPlayDecisionSE
            pbMoveSelection
            dorefresh = true
          elsif @page == 2 && (Settings::SUMMARY_EV_IV)
            pbPlayDecisionSE
            @pageTwoMode *= -1
            dorefresh = true
          elsif !@inbattle
            pbPlayDecisionSE
            dorefresh = pbOptions
          end
        elsif Input.trigger?(Input::UP) && @partyindex > 0
          oldindex = @partyindex
          pbGoToPrevious
          if @partyindex != oldindex
            @pageTwoMode = 1			
            pbChangePokemon
            dorefresh = true
          end
        elsif Input.trigger?(Input::DOWN) && @partyindex < @party.length - 1
          oldindex = @partyindex
          pbGoToNext
          if @partyindex != oldindex
            @pageTwoMode = 1
            pbChangePokemon
            dorefresh = true
          end
        elsif Input.trigger?(Input::LEFT) && !@pokemon.egg?
          oldpage = @page
          @page -= 1
          @page = 1 if @page < 1
          @page = 3 if @page > 3
          if @page != oldpage   # Move to next page
            @pageTwoMode = 1
            pbSEPlay("GUI summary change page")
            dorefresh = true
          end
        elsif Input.trigger?(Input::RIGHT) && !@pokemon.egg?
          oldpage = @page
          @page += 1
          @page = 1 if @page < 1
          @page = 3 if @page > 3
          if @page != oldpage   # Move to next page
            @pageTwoMode = 1	
            pbSEPlay("GUI summary change page")
            dorefresh = true
          end
        end
        drawPage(@page) if dorefresh
      end
      return @partyindex
    end
  end
  
  #===============================================================================
  #
  #===============================================================================
  class PokemonSummaryScreen
    def initialize(scene, inbattle = false)
      @scene = scene
      @inbattle = inbattle
    end
  
    def pbStartScreen(party, partyindex)
      @scene.pbStartScene(party, partyindex, @inbattle)
      ret = @scene.pbScene
      @scene.pbEndScene
      return ret
    end
  
    def pbStartForgetScreen(party, partyindex, move_to_learn)
      ret = -1
      @scene.pbStartForgetScene(party, partyindex, move_to_learn)
      loop do
        ret = @scene.pbChooseMoveToForget(move_to_learn)
        break if ret < 0 || !move_to_learn
        break if $DEBUG || !party[partyindex].moves[ret].hidden_move?
        pbMessage(_INTL("HM moves can't be forgotten now.")) { @scene.pbUpdate }
      end
      @scene.pbEndScene
      return ret
    end
  
    def pbStartChooseMoveScreen(party, partyindex, message)
      ret = -1
      @scene.pbStartForgetScene(party, partyindex, nil)
      pbMessage(message) { @scene.pbUpdate }
      loop do
        ret = @scene.pbChooseMoveToForget(nil)
        break if ret >= 0
        pbMessage(_INTL("You must choose a move!")) { @scene.pbUpdate }
      end
      @scene.pbEndScene
      return ret
    end
  end
  
  #===============================================================================
  #
  #===============================================================================
  def pbChooseMove(pokemon, variableNumber, nameVarNumber)
    return if !pokemon
    ret = -1
    pbFadeOutIn do
      scene = PokemonSummary_Scene.new
      screen = PokemonSummaryScreen.new(scene)
      ret = screen.pbStartForgetScreen([pokemon], 0, nil)
    end
    $game_variables[variableNumber] = ret
    if ret >= 0
      $game_variables[nameVarNumber] = pokemon.moves[ret].name
    else
      $game_variables[nameVarNumber] = ""
    end
    $game_map.need_refresh = true if $game_map
  end
  