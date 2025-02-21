# Zig Pathfinder

This is a small self-learning project to learn Zig and to demonstrate three path finding algorithms visually.

1. Depth First Search
2. Breadth First Search
3. A* Search

- **Maze Loading**: Loads a maze from a text file where walls are represented by `#` and empty paths by `.`.
- **Pathfinding Algorithms**: Supports both Depth-First Search and Breadth-First Search algorithms.
- **Real-Time Visualization**: Visualizes the search process in real-time using Raylib.
- **Customizable Start and End Points**: Allows specifying the start and end positions for the pathfinding.
- **Error Handling**: Includes robust error handling for invalid mazes and out-of-memory scenarios.

## Requirements

- **Zig**: Ensure you have Zig installed on your system. You can download it from [ziglang.org](https://ziglang.org/).
- **Raylib**: The application uses Raylib for rendering. Make sure Raylib is installed and properly linked.

## Installation

1. Clone the repository:
   ```sh
   git clone https://github.com/yourusername/zig-pathfinder.git
   cd zig-pathfinder
   ```

2. Build the project:
   ```sh
   zig build
   ```

3. Run the application:
See [Usage](#usage).

## Usage

### Command Line Arguments

The application requires the following command line arguments:

- `<file_path>`: Path to the maze file.
- `<start_row>`: Starting row position in the maze.
- `<start_col>`: Starting column position in the maze.
- `<end_row>`: Ending row position in the maze.
- `<end_col>`: Ending column position in the maze.
- `<search_type>`: Type of search algorithm to use (`depthfirst`, `astar` or `breadthfirst`).

### Example

```sh
./zig-out/bin/zig-pathfinder ./data/maze4 2 2 7 31 astar
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

Contributions are welcome! Please fork the repository and submit a pull request with your changes.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Acknowledgments

- **Raylib**: A simple and easy-to-use library to enjoy videogames programming. [Raylib GitHub](https://github.com/raysan5/raylib)
- **Zig**: A general-purpose programming language and toolchain for maintaining robust, optimal, and reusable software. [Zig GitHub](https://github.com/ziglang/zig)

## Contact

For any questions or suggestions, please open an issue on the GitHub repository or contact the maintainer directly.

---

Enjoy exploring mazes with Zig Pathfinder! 🚀
