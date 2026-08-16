#!/usr/bin/env bash
set -euo pipefail

THREADS=4
samples=(M117-bl M117-ch M117C1-bl M117C1-ch)
ref=data/ref/chrM.fa
results_dir=results

mkdir -p "$results_dir"

needs_update() {
    local out=$1
    shift
    if [ ! -s "$out" ]; then
        return 0
    fi
    local input
    for input in "$@"; do
        if [ "$input" -nt "$out" ]; then
            return 0
        fi
    done
    return 1
}

ref_index_current() {
    local ref=$1
    local ext
    if [ ! -s "${ref}.fai" ]; then
        return 1
    fi
    for ext in amb ann bwt pac sa; do
        if [ ! -s "${ref}.${ext}" ]; then
            return 1
        fi
    done
    if [ "$ref" -nt "${ref}.fai" ]; then
        return 1
    fi
    for ext in amb ann bwt pac sa; do
        if [ "$ref" -nt "${ref}.${ext}" ]; then
            return 1
        fi
    done
    return 0
}

if ! ref_index_current "$ref"; then
    samtools faidx "$ref"
    bwa index "$ref"
fi

for sample in "${samples[@]}"; do
    fq1="data/raw/${sample}_1.fq.gz"
    fq2="data/raw/${sample}_2.fq.gz"
    bam="${results_dir}/${sample}.bam"
    bai="${bam}.bai"
    vcfgz="${results_dir}/${sample}.vcf.gz"
    tbi="${vcfgz}.tbi"

    if needs_update "$bam" "$fq1" "$fq2" "$ref"; then
        bwa mem -t "$THREADS" -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" "$ref" "$fq1" "$fq2" | samtools sort -@ "$THREADS" -o "$bam"
    fi

    if needs_update "$bai" "$bam"; then
        samtools index -@ "$THREADS" "$bam"
    fi

    if [ ! -s "$vcfgz" ] || [ ! -s "$tbi" ] || needs_update "$tbi" "$fq1" "$fq2" "$ref" "$bam" "$vcfgz"; then
        lofreq call-parallel --pp-threads "$THREADS" --ref "$ref" "$bam" | bcftools view -O z -o "$vcfgz" -
        tabix -p vcf "$vcfgz"
    fi
done

collapsed="${results_dir}/collapsed.tsv"
vcf_inputs=()
for sample in "${samples[@]}"; do
    vcf_inputs+=("${results_dir}/${sample}.vcf.gz")
done

if [ ! -s "$collapsed" ] || needs_update "$collapsed" "${vcf_inputs[@]}"; then
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > "$collapsed"
    for sample in "${samples[@]}"; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" "${results_dir}/${sample}.vcf.gz" >> "$collapsed"
    done
fi