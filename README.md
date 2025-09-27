# Zig Path

An animated pathfinder written in Zig using Raylib, allowing you compare visually the way different algorithms traverse a maze.

## Algorithms implemented

1. Depth First Search
2. Breadth First Search
3. A* Search

## Live demo

You can try it in your browser at [https://heyes-jones.com/zigpath/zigpath.html](https://heyes-jones.com/zigpath/zigpath.html).

## Screenshots

<img width="647" alt="Image" src="https://github.com/user-attachments/assets/11ec61a9-016a-48ec-bb30-c9937420da6f" />
<img width="1372" alt="Image" src="https://github.com/user-attachments/assets/fb6606cb-d620-46fd-a776-44a6ecd90dbf" />

## Features

- **Maze Loading**: Add ascii mazes to the resources folder and choose one at load time.
- **Pathfinding Algorithms**: Supports a range of common search algorithms.
- **Real-Time Visualization**: Visualizes the search process in real-time using Raylib.
- **Customizable Start and End Points**: Allows specifying the start and end positions for the pathfinding.

## Requirements

- **Zig**: Ensure you have Zig installed on your system. You can download it from [ziglang.org](https://ziglang.org/). It must be version 0.15.1 or later compatible version.
- **Raylib**: The application uses Raylib for rendering. It will be downloaded and built as part of the Zig build process.

## Installation

### Run locally

To build for your native platform, follow these steps:

1. Clone the repository:
   ```sh
   git clone https://github.com/justinhj/zigpath.git
   cd zigpath
   ```

2. Build the project:
   ```sh
   zig build
   ```

3. Run the application:
See [Usage](#usage).

### Run in the browser

To build the wasm/Emscripten version, ensure you have the Emscripten SDK installed. You can follow the instructions at [Emscripten](https://emscripten.org/docs/getting_started/downloads.html).

``` sh
# Simply build
zig build -Dtarget=wasm32-emscripten -Doptimize=ReleaseSmall
# To also run in the browser
zig build -Dtarget=wasm32-emscripten -Doptimize=ReleaseSmall run
```

## Usage

``` sh
zig build run
# Or
zig build -Doptimize=ReleaseFast run
```

## Maze File Format

The maze file should be a text file where:
- `#` represents a wall.
- `.` represents an empty path.

Example maze file (`maze.txt`):

```
#.#.#.#.#
.#.#.#.#.
#.#.#.#.#
.#.#.#.#.
#.#.#.#.#
```

## Code Structure

- main.zig - The main program that orchestrates the pathfinding and visualization.
- queue.zig - Queue implemented via a circular buffer.
- binaryheap.zig - Binary heap used to provide efficient best first retrieval of next candidates.

## Resources

### Compile-Time Interfaces in Zig

Thanks to Jerry Thomas for this article explaining some common ways to implement interfaces in Zig.

[https://medium.com/@jerrythomas_in/exploring-compile-time-interfaces-in-zig-5c1a1a9e59fd]

### Maze Generation

[https://www.dcode.fr/maze-generator]

## Contributing

For bug or improvements feel free to make a pull request or open an issue.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Acknowledgments

- **Raylib**: A simple and easy-to-use library to enjoy videogames programming. [Raylib GitHub](https://github.com/raysan5/raylib)
- **Zig**: A general-purpose programming language and toolchain for maintaining robust, optimal, and reusable software. [Zig GitHub](https://github.com/ziglang/zig)

