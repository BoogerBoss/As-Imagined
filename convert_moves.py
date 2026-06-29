import json

input_file = "/home/rob/GodotAsImagined/pokeemerald-expansion/src/data/pokemon/all_learnables.json"
output_file = "/home/rob/GodotAsImagined/pokemon_moves.csv"

with open(input_file, "r") as f:
    data = json.load(f)

rows = 0

with open(output_file, "w") as f:
    f.write("Pokemon,Move\n")

    for pokemon, moves in data.items():
        for move in moves:
            f.write(f"{pokemon},{move}\n")
            rows += 1

print("Rows written:", rows)
