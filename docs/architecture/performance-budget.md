# Performance Budget

This document outlines the performance targets and budgets for the ProtonDrive Linux Client. Adhering to these budgets is crucial for delivering a responsive, efficient, and enjoyable user experience.

## Key Performance Metrics and Targets

| Metric               | Target      | Maximum     | Notes                                                              |
| :------------------- | :---------- | :---------- | :----------------------------------------------------------------- |
| **Installer Size**   | < 80 MB     | < 100 MB    | Compressed size of the AppImage/deb/rpm packages.                  |
| **RAM Usage (Idle)** | < 150 MB    | < 200 MB    | Memory footprint when the application is open but not actively syncing or being used. |
| **RAM Usage (Active)** | < 300 MB    | < 400 MB    | Memory footprint during active synchronization (e.g., uploading/downloading a large file). |
| **Cold Start Time**  | < 1.5 seconds | < 2 seconds | Time from application launch to the main window being fully rendered and interactive. |
| **UI Frame Rate**    | 60 FPS      | 45 FPS      | Smoothness of animations and user interface interactions.          |
| **Sync Time (1000 files)** | < 1 second  | < 2 seconds | Time taken to process 1000 file changes (e.g., hash, encrypt, queue for upload). |

## Monitoring and Profiling

Performance is continuously monitored using:

*   **Custom performance utilities**: Integrated into the application (`src/shared/utils/performance.ts`).
*   **Winston logging**: Performance events and potential bottlenecks are logged.
*   **Electron's built-in profilers**: For CPU and memory analysis.

Regular performance audits and profiling are conducted during development to ensure adherence to these targets.

## Optimization Strategies

*   **Lazy loading**: Load modules and resources only when needed.
*   **Efficient IPC**: Minimize inter-process communication overhead.
*   **Virtualization**: Use virtualized lists and tables for large datasets in the UI.
*   **Native modules**: Utilize Node.js native modules where performance is critical (e.g., for file system operations, heavy encryption).
*   **Database indexing**: Optimize SQLite queries with appropriate indices.
*   **Throttling/Debouncing**: Limit expensive operations in the UI and sync engine.
