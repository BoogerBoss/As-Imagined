class PokemonSummary_Scene
  if PluginManager.installed?("Generation 8 Pack Scripts")
    def pbFadeInAndShow(sprites, visiblesprites = nil)
        if visiblesprites
        visiblesprites.each do |i|
            if i[1] && sprites[i[0]] && !pbDisposed?(sprites[i[0]])
            sprites[i[0]].visible = true
            end
        end
        end
        @sprites["pokemon"].constrict([192, 192]) if @sprites["pokemon"] && !defined?(EliteBattle)
        numFrames = (Graphics.frame_rate * 0.4).floor
        alphaDiff = (255.0 / numFrames).ceil
        pbDeactivateWindows(sprites) {
        (0..numFrames).each do |j|
            pbSetSpritesToColor(sprites, Color.new(0, 0, 0, ((numFrames - j) * alphaDiff)))
            (block_given?) ? yield : pbUpdateSpriteHash(sprites)
        end
        }
    end

    alias __gen8__pbChangePokemon pbChangePokemon unless method_defined?(:__gen8__pbChangePokemon)
    def pbChangePokemon
        __gen8__pbChangePokemon
        @sprites["pokemon"].constrict([192, 192]) if !defined?(EliteBattle)
    end
  end
end