# Zig Path

An interative pathfinding visualizer written in Zig using Raylib.

1. Depth First Search
2. Breadth First Search
3. A* Search

- **Maze Loading**: Loads a maze from a text file where walls are represented by `#` and empty paths by `.`.
- **Pathfinding Algorithms**: Supports a range of common search algorithms.
- **Real-Time Visualization**: Visualizes the search process in real-time using Raylib.
- **Customizable Start and End Points**: Allows specifying the start and end positions for the pathfinding.

## Requirements

- **Zig**: Ensure you have Zig installed on your system. You can download it from [ziglang.org](https://ziglang.org/).
- **Raylib**: The application uses Raylib for rendering. It should be downloaded and built as part of the Zig build process.

## Installation

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

## Usage

### Command Line Arguments

The application requires the following command line argument(s):

- `<file_path>`: Path to the maze file.

### Example

```sh
./zig-out/bin/zigpath ./resources/maze5
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

---

Enjoy exploring mazes with Zig Pathfinder! 🚀
