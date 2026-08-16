#!/usr/bin/env bash
set -euo pipefail

results=$(pwd)/results
mkdir -p "$results"

for sample in M117-bl M117-ch M117C1-bl M117C1-ch; do
    bam="$results/${sample}.bam"
    bai="$results/${sample}.bam.bai"
    vcf_gz="$results/${sample}.vcf.gz"
    tbi="$results/${sample}.vcf.gz.tbi"

    # FastQC
    fastqc -o "$results" "data/raw/${sample}_1.${sample//-/_}2.fq.gz data/raw/${sample}_2.${sample//-/_}2.fq.gz"
    
    # BWA index for chrM
    samtools faidx data/ref/chrM.fa > /dev/null

    # BWA alignment (paired)
    bwa mem -t 4 data/ref/chrM.bed data/raw/${sample}_1.${sample//-/_}2.fq.gz data/raw/${sample}_2.${sample//-/_}2.fq.gz | \
        samtools view -b - > "$bam"

    # BAI index
    samtools index "$bam" > /dev/null

    # Variant calling with bcftools (using lofreq for filtering)
    bcftools view -Oz "$bam" | \
        lofreq --min-allele-freq 0.05 --max-allele-freq 0.95 --output "$vcf_gz"

    # TBI index
    tabix "$vcf_gz" > /dev/null

done

# Collapse variants across samples into a single table
samtools view -h results/M117-*.bam | \
    bcftools view -Oz - > /tmp/variants.bcf.gz

# Extract and format to TSV
echo "sample\tchrom\tpos\tref\talt\taf" > "$results/collapsed.tsv"
samtools view -h /tmp/variants.bcf.gz | \
    bcftools query -O json | \
    jq -r '.records[].{sample: "M117-", chrom: .chrom, pos: .pos, ref: .ref, alt: .alt, af: .af}' >> "$results/collapsed.tsv"

# Cleanup
rm /tmp/variants.bcf.gz

#!/usr/bin/env bash
set -euo pipefail