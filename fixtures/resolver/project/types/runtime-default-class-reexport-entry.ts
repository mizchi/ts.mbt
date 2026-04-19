class RuntimeGreeter {
  label: string

  constructor(label: string) {
    this.label = label
  }

  greet(name: string): string {
    return `${this.label}, ${name}`
  }
}

export default RuntimeGreeter
