#!/usr/bin/env bash
set -euo pipefail

mkdir -p results

# Index reference if not already indexed
if [[ ! -f data/ref/chrM.fa.bwt ]]; then
    bwa index data/ref/chrM.fa
fi

# Function to process a sample
process_sample() {
    local base=$1
    local r1="data/raw/${base}_1.fq.gz"
    local r2="data/raw/${base}_2.fq.gz"
    [[ -f "$r1" && -f "$r2" ]] || return 0

    # Skip if all outputs exist
    for out in results/"${base}".bam results/"${base}".bam.bai results/"${base}".vcf.gz results/"${base}".vcf.gz.tbi; do
        [[ -f "$out" ]] || break
    done
    [[ $? -eq 0 ]] && return 0

    # Align with BWA MEM, sort and index
    bwa mem -t 4 data/ref/chrM.fa "$r1" "$r2" |
        samtools view -@ 2 -b - > results/"${base}".bam
    samtools sort -@ 2 -o results/"${base}".bam.bai results/"${base}".bam
    samtools index results/"${base}".bam.bai

    # Variant calling with lofreq
    lofreq call-acgt \
        --no-indel-prior --min-MQ 30 --min-base-quality 20 \
        -r chrM.fa \
        -O results/${base}.vcf.gz \
        data/ref/chrM.fa \
        results/"${base}".bam

    # Index VCF
    bcftools index -t results/${base}.vcf.gz
}

# Process all samples
for sample in M117-bl M117-ch M117C1-bl M117C1-ch; do
    process_sample "$sample"
done

# Collapse VCFs into collapsed.tsv
output="results/collapsed.tsv"
echo -e "sample\tchrom\tpos\tref\talt\taf" > "$output"

for sample in M117-bl M117-ch M117C1-bl M117C1-ch; do
    # Extract heterozygous SNPs with AF>0.05 using SnpSift
    vcf="results/${sample}.vcf.gz"
    tmp=$(mktemp)
    gunzip -c "$vcf" |
        java -jar $(which snpsift.jar) effect - |
        awk '$6=="missense_variant" && $8/100 > 0.05 {print "'"$sample"'\t$1"\t$2"\t$4"\t"$5"\t"$8/100}' >> "$tmp"
    # Append to collapsed.tsv
    cat "$tmp" >> "$output"
    rm -f "$tmp"
done

# Ensure tab-separated and sorted (optional)
sort -k1,1 -k2,2n -o "$output" "$output"

exit 0