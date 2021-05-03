package com.amazon.aoc.models;

import com.amazon.aoc.fileconfigs.FileConfig;

public class TemplateFileConfig implements FileConfig {
  private String path;

  public TemplateFileConfig(String path) {
    this.path = path;
  }

  @Override
  public String getPath() {
    return path;
  }
}
